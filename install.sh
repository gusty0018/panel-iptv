cat > /root/panel/install.sh << 'EOS'
#!/bin/bash
apt update -y
apt install -y python3 python3-pip sqlite3 curl
pip3 install flask --break-system-packages 2>/dev/null || pip3 install flask
mkdir -p /root/panel
cd /root/panel
cat > app.py << 'PY'
from flask import Flask, request, redirect, Response, jsonify
import sqlite3
app = Flask(__name__)
DB="/root/panel/panel.db"
ADMIN_USER="gustyadmin"; ADMIN_PASS="Gusty0018@@"
def init():
    import sqlite3
    con=sqlite3.connect(DB)
    con.execute("CREATE TABLE IF NOT EXISTS canales (id INTEGER PRIMARY KEY, nombre TEXT, url TEXT, orden INTEGER DEFAULT 0)")
    con.execute("CREATE TABLE IF NOT EXISTS usuarios (id INTEGER PRIMARY KEY, user TEXT UNIQUE, pass TEXT, expira DATE, activo INTEGER DEFAULT 1)")
    try: con.execute("ALTER TABLE canales ADD COLUMN orden INTEGER DEFAULT 0")
    except: pass
    con.commit()
init()
def valid_user(u,p):
    import sqlite3
    con=sqlite3.connect(DB)
    return con.execute("SELECT * FROM usuarios WHERE user=? AND pass=? AND activo=1",(u,p)).fetchone()
@app.route("/login", methods=["GET","POST"])
def login():
    from flask import request, redirect
    if request.method=="POST" and request.form.get("user")==ADMIN_USER and request.form.get("pass")==ADMIN_PASS:
        r=redirect("/admin"); r.set_cookie("auth","ok"); return r
    return '<form method="post"><input name="user"><input name="pass" type="password"><button>Entrar</button></form>'
@app.route("/admin")
def admin():
    if __import__("flask").request.cookies.get("auth")!="ok": return __import__("flask").redirect("/login")
    import sqlite3
    con=sqlite3.connect(DB); canales=con.execute("SELECT id,nombre,url,orden FROM canales ORDER BY orden ASC").fetchall()
    total=len(canales)+1
    page=f'<html><body style="background:#111;color:#fff"><h2>Panel {total-1} canales</h2><form method="post" action="/add"><input name="nombre" required><input name="url" required><input name="posicion" type="number" placeholder="Pos"><button>Agregar</button></form><hr><form method="post" action="/saveorder">'
    for i,c in enumerate(canales):
        page+=f'<div>{i+1}. {c[1]} <a href="/up/{c[0]}">UP</a> <a href="/down/{c[0]}">DN</a> <a href="/del/{c[0]}">X</a></div>'
    page+='<button>GUARDAR</button></form></body></html>'
    return page
@app.route("/add", methods=["POST"])
def add():
    import sqlite3
    n=__import__("flask").request.form["nombre"]; u=__import__("flask").request.form["url"]; ps=__import__("flask").request.form.get("posicion","").strip()
    con=sqlite3.connect(DB); cs=con.execute("SELECT id,orden FROM canales ORDER BY orden").fetchall(); tot=len(cs); nv=tot
    if ps!="":
        try:
            p=int(ps)
            nv=p-1
            for cid,ordn in cs:
                if ordn>=nv: con.execute("UPDATE canales SET orden=? WHERE id=?",(ordn+1,cid))
            con.commit()
        except: nv=tot
    con.execute("INSERT INTO canales (nombre,url,orden) VALUES (?,?,?)",(n,u,nv)); con.commit(); return __import__("flask").redirect("/admin")
@app.route("/del/<int:id>")
def dele(id):
    import sqlite3; con=sqlite3.connect(DB); con.execute("DELETE FROM canales WHERE id=?",(id,)); con.commit(); return __import__("flask").redirect("/admin")
@app.route("/up/<int:id>")
def up(id):
    import sqlite3; con=sqlite3.connect(DB); cur=con.execute("SELECT id,orden FROM canales ORDER BY orden").fetchall()
    for i in range(len(cur)):
        if cur[i][0]==id and i>0: con.execute("UPDATE canales SET orden=? WHERE id=?",(cur[i-1][1],id)); con.execute("UPDATE canales SET orden=? WHERE id=?",(cur[i][1],cur[i-1][0])); con.commit(); break
    return __import__("flask").redirect("/admin")
@app.route("/down/<int:id>")
def down(id):
    import sqlite3; con=sqlite3.connect(DB); cur=con.execute("SELECT id,orden FROM canales ORDER BY orden").fetchall()
    for i in range(len(cur)):
        if cur[i][0]==id and i < len(cur)-1: con.execute("UPDATE canales SET orden=? WHERE id=?",(cur[i+1][1],id)); con.execute("UPDATE canales SET orden=? WHERE id=?",(cur[i][1],cur[i+1][0])); con.commit(); break
    return __import__("flask").redirect("/admin")
def get_m3u():
    import sqlite3; con=sqlite3.connect(DB); cs=con.execute("SELECT nombre,url FROM canales ORDER BY orden ASC").fetchall(); m="#EXTM3U\n"
    for nom,url in cs: m+=f"#EXTINF:-1,{nom}\n{url}\n"
    return m
@app.route("/get.php")
def get3u():
    from flask import request, Response
    u=request.args.get("username"); p=request.args.get("password")
    if not valid_user(u,p): return "Vencido",403
    return Response(get_m3u(), mimetype='text/plain')
@app.route("/player_api.php")
def player_api():
    from flask import request, jsonify
    u=request.args.get("username"); p=request.args.get("password"); a=request.args.get("action")
    if not valid_user(u,p): return jsonify({"user_info":{"auth":0}})
    import sqlite3; con=sqlite3.connect(DB); cs=con.execute("SELECT id,nombre,url,orden FROM canales ORDER BY orden ASC").fetchall()
    if a=="get_live_categories": return jsonify([{"category_id":"1","category_name":"CANALES","parent_id":0}])
    if a=="get_live_streams": return jsonify([{"num":c[3]+1,"name":c[1],"stream_type":"live","stream_id":c[0],"category_id":"1","direct_source":c[2]} for c in cs])
    return jsonify({"user_info":{"username":u,"auth":1,"status":"Active","exp_date":"9999999999","max_connections":"1"},"server_info":{"url":"163.176.139.218","port":"80"}})
@app.route("/live/<u>/<p>/<path:s>")
def live(u,p,s):
    if not valid_user(u,p): return "Auth fail",403
    import sqlite3; con=sqlite3.connect(DB); sid=int(s.split(".")[0]); ch=con.execute("SELECT url FROM canales WHERE id=?",(sid,)).fetchone()
    return __import__("flask").redirect(ch[0]) if ch else ("No existe",404)
@app.route("/xmltv.php")
def xmltv(): return __import__("flask").Response("<tv></tv>", mimetype='text/xml')
@app.route("/")
def index(): return __import__("flask").redirect("/admin")
app.run(host='0.0.0.0',port=80)
PY
cat > /etc/systemd/system/panel.service << 'SERVICE'
[Unit]
Description=Panel IPTV
After=network.target
[Service]
User=root
WorkingDirectory=/root/panel
ExecStart=/usr/bin/python3 /root/panel/app.py
Restart=always
[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload
systemctl enable panel
systemctl restart panel
echo "PANEL INSTALADO OK http://$(curl -s ifconfig.me)/admin gustyadmin / Gusty0018@@"
EOS
cat /root/panel/install.sh
