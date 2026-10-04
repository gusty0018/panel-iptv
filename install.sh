#!/bin/bash
# INSTALADOR PANEL IPTV GUSTY - VERSION FINAL CON POSICION
set -e
echo ">>> Instalando Panel IPTV Gusty..."

apt update -y
apt install -y python3 python3-pip sqlite3 curl
pip3 install flask --break-system-packages 2>/dev/null || pip3 install flask

mkdir -p /root/panel
cd /root/panel

cat > app.py << 'PY'
from flask import Flask, request, redirect, Response, jsonify
import sqlite3, datetime
app = Flask(__name__)
DB="/root/panel/panel.db"
def init():
    con=sqlite3.connect(DB)
    con.execute("CREATE TABLE IF NOT EXISTS canales (id INTEGER PRIMARY KEY, nombre TEXT, url TEXT, orden INTEGER DEFAULT 0)")
    con.execute("CREATE TABLE IF NOT EXISTS usuarios (id INTEGER PRIMARY KEY, user TEXT UNIQUE, pass TEXT, expira DATE, activo INTEGER DEFAULT 1)")
    try: con.execute("ALTER TABLE canales ADD COLUMN orden INTEGER DEFAULT 0")
    except: pass
    con.commit()
init()
ADMIN_USER="gustyadmin"; ADMIN_PASS="Gusty0018@@"
def check_exp():
    try:
        con=sqlite3.connect(DB); con.execute("UPDATE usuarios SET activo=0 WHERE expira <?", (datetime.date.today().isoformat(),)); con.commit()
    except: pass
def valid_user(u,p):
    check_exp()
    con=sqlite3.connect(DB)
    return con.execute("SELECT * FROM usuarios WHERE user=? AND pass=? AND activo=1",(u,p)).fetchone()
@app.route("/login", methods=["GET","POST"])
def login():
    if request.method=="POST" and request.form.get("user")==ADMIN_USER and request.form.get("pass")==ADMIN_PASS:
        r=redirect("/admin"); r.set_cookie("auth","ok"); return r
    return '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="background:#0e0e0e;color:#fff;font-family:sans-serif;display:flex;justify-content:center;align-items:center;height:100vh"><form method="post" style="background:#222;padding:20px;border-radius:12px;width:300px"><h3>Panel Login</h3><input name="user" placeholder="Usuario" style="width:100%;padding:10px;margin:5px 0"><input name="pass" type="password" placeholder="Pass" style="width:100%;padding:10px;margin:5px 0"><button style="width:100%;padding:12px;background:#2a7ae2;color:#fff;border:0;border-radius:8px;margin-top:10px">Entrar</button></form></body></html>'
@app.route("/admin")
def admin():
    if request.cookies.get("auth")!="ok": return redirect("/login")
    con=sqlite3.connect(DB); canales=con.execute("SELECT id,nombre,url,orden FROM canales ORDER BY orden ASC").fetchall()
    total=len(canales)+1
    page=f'''
<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="background:#111;color:#fff;font-family:sans-serif;padding:10px">
<h2>Panel - {total-1} canales</h2><a href="/admin/users" style="color:#4fc3f7">USUARIOS</a><hr>
<h3>Agregar Canal en posicion que quieras</h3>
<form method="post" action="/add" style="background:#222;padding:12px;border-radius:10px;display:flex;gap:8px;flex-wrap:wrap;align-items:center">
<input name="nombre" placeholder="Nombre ej: ESPN" required style="padding:10px;flex:1;min-width:120px">
<input name="url" placeholder="https://...m3u8" required style="padding:10px;flex:2;min-width:200px">
<input name="posicion" type="number" min="1" max="{total}" placeholder="Pos #{total}" style="padding:10px;width:80px;background:#111;color:#fff;border:1px solid #555;border-radius:6px">
<button style="padding:10px 18px;background:#2a7ae2;color:#fff;border:0;border-radius:8px;font-weight:bold">Agregar en pos</button>
</form>
<small style="color:#888">Si no pones posicion va al final. Si pones 5, entra en el lugar 5 y corre los demas.</small>
<hr><form method="post" action="/saveorder">'''
    for i,c in enumerate(canales):
        cid, nom, url, ordn = c[0], c[1], c[2], c[3]
        page+=f'<div style="background:#222;padding:10px;margin:8px 0;display:flex;gap:6px;align-items:center;border-radius:8px"><input type="number" name="pos_{cid}" value="{i+1}" style="width:45px;padding:8px"><div style="flex:1"><b>{i+1}. {nom}</b><br><small style="color:#888;word-break:break-all">{url[:70]}</small></div><a href="/up/{cid}" style="padding:10px;background:#444;color:#fff;text-decoration:none;border-radius:6px">A</a><a href="/down/{cid}" style="padding:10px;background:#444;color:#fff;text-decoration:none;border-radius:6px">V</a><a href="/edit/{cid}" style="padding:10px;background:#1e3a5a;color:#7ab0ff;text-decoration:none;border-radius:6px">EDIT</a><a href="/del/{cid}" style="padding:10px;background:#5a1a1a;color:#ff8888;text-decoration:none;border-radius:6px">X</a></div>'
    page+='<button style="padding:14px;background:#2a7ae2;color:#fff;width:100%;margin-top:12px;border:0;border-radius:10px;font-weight:bold">GUARDAR ORDEN</button></form></body></html>'
    return page
@app.route("/saveorder", methods=["POST"])
def saveorder():
    con=sqlite3.connect(DB); ids=con.execute("SELECT id FROM canales").fetchall(); lista=[]
    for (cid,) in ids:
        v=request.form.get(f"pos_{cid}")
        if v:
            try: lista.append((int(v), cid))
            except: pass
    lista.sort(key=lambda x: x[0])
    for idx,(pos,cid) in enumerate(lista):
        con.execute("UPDATE canales SET orden=? WHERE id=?", (idx, cid))
    con.commit()
    return redirect("/admin")
@app.route("/up/<int:id>")
def up(id):
    con=sqlite3.connect(DB); cur=con.execute("SELECT id,orden FROM canales ORDER BY orden").fetchall()
    for i in range(len(cur)):
        if cur[i][0]==id and i>0:
            con.execute("UPDATE canales SET orden=? WHERE id=?", (cur[i-1][1], id)); con.execute("UPDATE canales SET orden=? WHERE id=?", (cur[i][1], cur[i-1][0])); con.commit(); break
    return redirect("/admin")
@app.route("/down/<int:id>")
def down(id):
    con=sqlite3.connect(DB); cur=con.execute("SELECT id,orden FROM canales ORDER BY orden").fetchall()
    for i in range(len(cur)):
        if cur[i][0]==id and i < len(cur)-1:
            con.execute("UPDATE canales SET orden=? WHERE id=?", (cur[i+1][1], id)); con.execute("UPDATE canales SET orden=? WHERE id=?", (cur[i][1], cur[i+1][0])); con.commit(); break
    return redirect("/admin")
@app.route("/add", methods=["POST"])
def add():
    nombre=request.form["nombre"]
    url=request.form["url"]
    pos_str=request.form.get("posicion","").strip()
    con=sqlite3.connect(DB)
    canales=con.execute("SELECT id,orden FROM canales ORDER BY orden").fetchall()
    total=len(canales)
    if pos_str=="":
        nuevo_orden=total
    else:
        try:
            pos=int(pos_str)
            if pos < 1: pos=1
            if pos > total+1: pos=total+1
            nuevo_orden=pos-1
            for cid, orden in canales:
                if orden >= nuevo_orden:
                    con.execute("UPDATE canales SET orden=? WHERE id=?", (orden+1, cid))
            con.commit()
        except:
            nuevo_orden=total
    con.execute("INSERT INTO canales (nombre,url,orden) VALUES (?,?,?)", (nombre, url, nuevo_orden))
    con.commit()
    cur=con.execute("SELECT id FROM canales ORDER BY orden ASC").fetchall()
    for idx,(cid,) in enumerate(cur):
        con.execute("UPDATE canales SET orden=? WHERE id=?", (idx, cid))
    con.commit()
    return redirect("/admin")
@app.route("/del/<int:id>")
def dele(id):
    con=sqlite3.connect(DB); con.execute("DELETE FROM canales WHERE id=?",(id,)); con.commit()
    cur=con.execute("SELECT id FROM canales ORDER BY orden ASC").fetchall()
    for idx,(cid,) in enumerate(cur):
        con.execute("UPDATE canales SET orden=? WHERE id=?", (idx, cid))
    con.commit()
    return redirect("/admin")
@app.route("/edit/<int:id>", methods=["GET","POST"])
def edit(id):
    if request.cookies.get("auth")!="ok": return redirect("/login")
    con=sqlite3.connect(DB)
    if request.method=="POST":
        con.execute("UPDATE canales SET nombre=?, url=? WHERE id=?", (request.form["nombre"], request.form["url"], id)); con.commit(); return redirect("/admin")
    c=con.execute("SELECT id,nombre,url FROM canales WHERE id=?",(id,)).fetchone()
    return f'<body style="background:#111;color:#fff;padding:20px;font-family:sans-serif"><h2>Editar #{c[0]}</h2><form method="post"><input name="nombre" value="{c[1]}" style="width:95%;padding:10px"><br><br><input name="url" value="{c[2]}" style="width:95%;padding:10px"><br><br><button style="padding:12px 20px;background:#2a7ae2;color:#fff;border:0;border-radius:8px">Guardar</button> <a href="/admin" style="color:#aaa">Cancelar</a></form></body>'
@app.route("/admin/users")
def users_page():
    if request.cookies.get("auth")!="ok": return redirect("/login")
    con=sqlite3.connect(DB); users=con.execute("SELECT * FROM usuarios").fetchall()
    html='<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="background:#111;color:#fff;font-family:sans-serif;padding:10px"><a href="/admin">Canales</a><h2>Usuarios</h2><form method="post" action="/adduser" style="background:#222;padding:10px;border-radius:10px"><input name="user" placeholder="Usuario" required><input name="pass" placeholder="Pass" required><input name="expira" type="date" required><button>Crear</button></form><hr>'
    for u in users: html+=f'{u[1]} - {u[3]} - activo:{u[4]} <a href="/deluser/{u[0]}" style="color:red">Borrar</a><br>'
    html+='</body></html>'
    return html
@app.route("/adduser", methods=["POST"])
def adduser():
    con=sqlite3.connect(DB); con.execute("INSERT INTO usuarios (user,pass,expira,activo) VALUES (?,?,?,1)",(request.form["user"],request.form["pass"],request.form["expira"])); con.commit(); return redirect("/admin/users")
@app.route("/deluser/<int:id>")
def deluser(id):
    con=sqlite3.connect(DB); con.execute("DELETE FROM usuarios WHERE id=?",(id,)); con.commit(); return redirect("/admin/users")
def get_m3u():
    con=sqlite3.connect(DB); canales=con.execute("SELECT nombre,url FROM canales ORDER BY orden ASC").fetchall(); m="#EXTM3U\n"
    for nom,url in canales: m+=f'#EXTINF:-1,{nom}\n{url}\n'
    return m
@app.route("/get.php")
def get3u():
    u=request.args.get("username"); p=request.args.get("password")
    if not valid_user(u,p): return "Vencido",403
    return Response(get_m3u(), mimetype='text/plain')
@app.route("/player_api.php")
def player_api():
    u=request.args.get("username"); p=request.args.get("password"); act=request.args.get("action")
    if not valid_user(u,p): return jsonify({"user_info":{"auth":0}})
    con=sqlite3.connect(DB); canales=con.execute("SELECT id,nombre,url,orden FROM canales ORDER BY orden ASC").fetchall()
    if act=="get_live_categories": return jsonify([{"category_id":"1","category_name":"CANALES","parent_id":0}])
    if act=="get_live_streams":
        return jsonify([{"num":c[3]+1,"name":c[1],"stream_type":"live","stream_id":c[0],"category_id":"1","direct_source":c[2]} for c in canales])
    return jsonify({"user_info":{"username":u,"auth":1,"status":"Active","exp_date":"9999999999","max_connections":"1"},"server_info":{"url":"163.176.139.218","port":"80"}})
@app.route("/live/<username>/<password>/<path:stream>")
def live(username,password,stream):
    if not valid_user(username,password): return "Auth fail",403
    sid=int(stream.split(".")[0]); con=sqlite3.connect(DB); ch=con.execute("SELECT url FROM canales WHERE id=?",(sid,)).fetchone()
    return redirect(ch[0]) if ch else ("No existe",404)
@app.route("/xmltv.php")
def xmltv(): return Response("<tv></tv>", mimetype='text/xml')
@app.route("/")
def index():
    return redirect("/admin")
if __name__ == "__main__":
    app.run(host='0.0.0.0', port=80)
PY

cat > /etc/systemd/system/panel.service << 'SERVICE'
[Unit]
Description=Panel IPTV Gusty
After=network.target
[Service]
User=root
WorkingDirectory=/root/panel
ExecStart=/usr/bin/python3 /root/panel/app.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable panel
systemctl restart panel

IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
echo ""
echo "========================================"
echo " PANEL INSTALADO OK"
echo " URL: http://$IP/admin"
echo " User: gustyadmin"
echo " Pass: Gusty0018@@"
echo "========================================"
systemctl status panel --no-pager -l
