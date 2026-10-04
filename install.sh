#!/bin/bash
# PANEL IPTV GUSTY - VERSION 2.0 SEGURA - PIDE USUARIO Y CLAVE
set -e

echo "========================================"
echo " PANEL IPTV GUSTY v2.0 - INSTALADOR SEGURO"
echo "========================================"
echo ""

read -p "Usuario admin [gustyadmin]: " INPUT_USER
ADMIN_USER=${INPUT_USER:-gustyadmin}

read -s -p "Clave admin [dejar vacio para generar automatica]: " INPUT_PASS
echo ""
if [ -z "$INPUT_PASS" ]; then
  ADMIN_PASS=$(openssl rand -base64 10 | tr -dc 'a-zA-Z0-9' | head -c 12)
  echo ">> Clave auto-generada: $ADMIN_PASS"
else
  ADMIN_PASS=$INPUT_PASS
fi

echo ""
echo ">>> Instalando con usuario: $ADMIN_USER"

apt update -y
apt install -y python3 python3-pip sqlite3 curl openssl
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
ADMIN_USER="__ADMIN_USER__"
ADMIN_PASS="__ADMIN_PASS__"
def valid_user(u,p):
    con=sqlite3.connect(DB)
    return con.execute("SELECT * FROM usuarios WHERE user=? AND pass=? AND activo=1",(u,p)).fetchone()
@app.route("/login", methods=["GET","POST"])
def login():
    if request.method=="POST" and request.form.get("user")==ADMIN_USER and request.form.get("pass")==ADMIN_PASS:
        r=redirect("/admin"); r.set_cookie("auth","ok"); return r
    return '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="background:#0e0e0e;color:#fff;display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif"><form method="post" style="background:#222;padding:20px;border-radius:12px;width:300px"><h3>Panel Login</h3><input name="user" placeholder="Usuario" style="width:100%;padding:10px;margin:5px 0"><input name="pass" type="password" placeholder="Pass" style="width:100%;padding:10px;margin:5px 0"><button style="width:100%;padding:12px;background:#2a7ae2;color:#fff;border:0;border-radius:8px">Entrar</button></form></body></html>'
@app.route("/admin")
@app.route("/admin/")
def admin():
    if request.cookies.get("auth")!="ok": return redirect("/login")
    con=sqlite3.connect(DB); canales=con.execute("SELECT id,nombre,url,orden FROM canales ORDER BY orden ASC").fetchall(); total=len(canales)+1
    page=f'<html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta charset="utf-8"></head><body style="background:#111;color:#fff;font-family:sans-serif;padding:10px"><h2>Panel - {total-1} canales</h2><a href="/admin/users" style="color:#4fc3f7">USUARIOS</a><hr><h3>Agregar Canal</h3><form method="post" action="/add" style="background:#222;padding:15px;border-radius:12px;display:flex;gap:8px;flex-wrap:wrap"><input name="nombre" placeholder="Nombre" required style="padding:10px;flex:1"><input name="url" placeholder="m3u8" required style="padding:10px;flex:2"><input name="posicion" type="number" min="1" max="{total}" placeholder="Pos #{total}" style="width:80px"><button style="padding:10px 20px;background:#2a7ae2;color:#fff;border:0;border-radius:8px">Agregar</button></form><hr><form method="post" action="/saveorder">'
    for i,c in enumerate(canales):
        page+=f'<div style="background:#222;padding:12px;margin:8px 0;border-radius:10px;display:flex;gap:8px;align-items:center"><input type="number" name="pos_{c[0]}" value="{i+1}" style="width:50px"><div style="flex:1"><b>{i+1}. {c[1]}</b></div><a href="/up/{c[0]}" style="background:#333;padding:8px 12px;border-radius:8px;color:#fff;text-decoration:none">▲</a><a href="/down/{c[0]}" style="background:#333;padding:8px 12px;border-radius:8px;color:#fff;text-decoration:none">▼</a><a href="/del/{c[0]}" style="background:#5a1a1a;padding:8px 12px;border-radius:8px;color:#ff7777;text-decoration:none">X</a></div>'
    page+='<button style="width:100%;padding:14px;background:#2a7ae2;color:#fff;border:0;border-radius:10px;margin-top:10px">GUARDAR ORDEN</button></form></body></html>'; return page
@app.route("/saveorder", methods=["POST"])
def saveorder():
    con=sqlite3.connect(DB); lista=[]
    for (cid,) in con.execute("SELECT id FROM canales").fetchall():
        v=request.form.get(f"pos_{cid}")
        if v:
            try: lista.append((int(v),cid))
            except: pass
    lista.sort(key=lambda x:x[0])
    for idx,(pos,cid) in enumerate(lista): con.execute("UPDATE canales SET orden=? WHERE id=?",(idx,cid))
    con.commit(); return redirect("/admin")
@app.route("/up/<int:id>")
def up(id):
    con=sqlite3.connect(DB); cur=con.execute("SELECT id,orden FROM canales ORDER BY orden").fetchall()
    for i in range(len(cur)):
        if cur[i][0]==id and i>0: con.execute("UPDATE canales SET orden=? WHERE id=?",(cur[i-1][1],id)); con.execute("UPDATE canales SET orden=? WHERE id=?",(cur[i][1],cur[i-1][0])); con.commit(); break
    return redirect("/admin")
@app.route("/down/<int:id>")
def down(id):
    con=sqlite3.connect(DB); cur=con.execute("SELECT id,orden FROM canales ORDER BY orden").fetchall()
    for i in range(len(cur)):
        if cur[i][0]==id and i < len(cur)-1: con.execute("UPDATE canales SET orden=? WHERE id=?",(cur[i+1][1],id)); con.execute("UPDATE canales SET orden=? WHERE id=?",(cur[i][1],cur[i+1][0])); con.commit(); break
    return redirect("/admin")
@app.route("/add", methods=["POST"])
def add():
    n=request.form["nombre"]; u=request.form["url"]; ps=request.form.get("posicion","").strip(); con=sqlite3.connect(DB); cs=con.execute("SELECT id,orden FROM canales ORDER BY orden").fetchall(); tot=len(cs); nv=tot
    if ps.isdigit():
        p=int(ps); nv=p-1
        for cid,ordn in cs:
            if ordn>=nv: con.execute("UPDATE canales SET orden=? WHERE id=?",(ordn+1,cid))
    con.execute("INSERT INTO canales (nombre,url,orden) VALUES (?,?,?)",(n,u,nv)); con.commit(); cur=con.execute("SELECT id FROM canales ORDER BY orden ASC").fetchall()
    for idx,(cid,) in enumerate(cur): con.execute("UPDATE canales SET orden=? WHERE id=?",(idx,cid))
    con.commit(); return redirect("/admin")
@app.route("/del/<int:id>")
def dele(id):
    con=sqlite3.connect(DB); con.execute("DELETE FROM canales WHERE id=?",(id,)); con.commit(); return redirect("/admin")
@app.route("/admin/users")
@app.route("/admin/users/")
def users_page():
    if request.cookies.get("auth")!="ok": return redirect("/login")
    con=sqlite3.connect(DB); us=con.execute("SELECT id,user,pass,expira FROM usuarios ORDER BY id DESC").fetchall()
    h='<html><body style="background:#111;color:#fff;padding:15px;font-family:sans-serif"><a href="/admin" style="color:#4fc3f7">← Canales</a><h2>Usuarios</h2><form method="post" action="/adduser" style="background:#222;padding:15px;border-radius:12px"><input name="user" placeholder="Usuario" required><input name="pass" placeholder="Pass" required><input name="expira" type="date" required><button>CREAR</button></form><hr>'
    for x in us: h+=f'{x[1]} | {x[2]} | {x[3]} <a href="/deluser/{x[0]}" style="color:red">[X]</a><br>'
    return h+'</body></html>'
@app.route("/adduser", methods=["POST"])
def adduser():
    try: con=sqlite3.connect(DB); con.execute("INSERT INTO usuarios (user,pass,expira,activo) VALUES (?,?,?,1)",(request.form["user"],request.form["pass"],request.form["expira"])); con.commit()
    except Exception as e: return f'Error {e} <a href="/admin/users">Volver</a>'
    return redirect("/admin/users")
@app.route("/deluser/<int:id>")
def deluser(id):
    con=sqlite3.connect(DB); con.execute("DELETE FROM usuarios WHERE id=?",(id,)); con.commit(); return redirect("/admin/users")
def get_m3u():
    con=sqlite3.connect(DB); cs=con.execute("SELECT nombre,url FROM canales ORDER BY orden ASC").fetchall(); m="#EXTM3U\n"
    for nom,url in cs: m+=f"#EXTINF:-1,{nom}\n{url}\n"
    return m
@app.route("/get.php")
def get3u():
    u=request.args.get("username"); p=request.args.get("password")
    if not valid_user(u,p): return "Vencido",403
    return Response(get_m3u(), mimetype='text/plain')
@app.route("/player_api.php")
def player_api():
    u=request.args.get("username"); p=request.args.get("password"); a=request.args.get("action")
    if not valid_user(u,p): return jsonify({"user_info":{"auth":0}})
    con=sqlite3.connect(DB); cs=con.execute("SELECT id,nombre,url,orden FROM canales ORDER BY orden ASC").fetchall()
    if a=="get_live_categories": return jsonify([{"category_id":"1","category_name":"CANALES","parent_id":0}])
    if a=="get_live_streams": return jsonify([{"num":c[3]+1,"name":c[1],"stream_type":"live","stream_id":c[0],"category_id":"1","direct_source":c[2]} for c in cs])
    return jsonify({"user_info":{"username":u,"auth":1,"status":"Active","exp_date":"9999999999","max_connections":"1"},"server_info":{"url":"0.0.0.0","port":"80"}})
@app.route("/live/<username>/<password>/<path:stream>")
def live(username,password,stream):
    if not valid_user(username,password): return "Auth fail",403
    sid=int(stream.split(".")[0]); con=sqlite3.connect(DB); ch=con.execute("SELECT url FROM canales WHERE id=?",(sid,)).fetchone()
    return redirect(ch[0]) if ch else ("No existe",404)
@app.route("/xmltv.php")
def xmltv(): return Response("<tv></tv>", mimetype='text/xml')
@app.route("/")
def index(): return redirect("/admin")
app.run(host='0.0.0.0',port=80)
PY

sed -i "s/__ADMIN_USER__/$ADMIN_USER/g; s/__ADMIN_PASS__/$ADMIN_PASS/g" /root/panel/app.py

cat > /etc/systemd/system/panel.service << SERVICE
[Unit]
Description=Panel IPTV Gusty v2.0
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
sleep 2

IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
echo ""
echo "========================================"
echo " PANEL INSTALADO CORRECTAMENTE"
echo " URL: http://$IP/admin"
echo " User: $ADMIN_USER"
echo " Pass: $ADMIN_PASS"
echo "========================================"
echo " GUARDA ESTOS DATOS, NO ESTAN EN GITHUB"
echo ""
