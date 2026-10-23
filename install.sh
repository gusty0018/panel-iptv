#!/bin/bash
# PANEL IPTV GUSTY - VERSION 3.0 PRO - Referer/Origin/UA + Proxy HLS
set -e

echo "========================================"
echo " PANEL IPTV GUSTY v3.0 PRO"
echo "========================================"

read -p "Usuario admin [admin]: " INPUT_USER
ADMIN_USER=${INPUT_USER:-admin}

read -p "Clave admin [1234]: " INPUT_PASS
ADMIN_PASS=${INPUT_PASS:-1234}

echo ""
echo ">>> Instalando con usuario: $ADMIN_USER / $ADMIN_PASS"

apt update -y
apt install -y python3 python3-pip sqlite3 curl
pip3 install flask requests --break-system-packages 2>/dev/null || pip3 install flask requests

mkdir -p /root/panel
mkdir -p /root/backups-panel
cd /root/panel

# Backup
if [ -f app.py ]; then
  FECHA=$(date +%Y-%m-%d_%H-%M)
  cp app.py /root/backups-panel/app.py_BACKUP_$FECHA.py
  cp panel.db /root/backups-panel/panel.db_BACKUP_$FECHA.db 2>/dev/null || true
fi

cat > app.py << 'PY'
from flask import Flask, request, redirect, Response, jsonify
import sqlite3, requests, urllib.parse
app = Flask(__name__)
DB="/root/panel/panel.db"

def init():
    con=sqlite3.connect(DB)
    con.execute("CREATE TABLE IF NOT EXISTS canales (id INTEGER PRIMARY KEY, nombre TEXT, url TEXT, orden INTEGER DEFAULT 0)")
    con.execute("CREATE TABLE IF NOT EXISTS usuarios (id INTEGER PRIMARY KEY, user TEXT UNIQUE, pass TEXT, expira DATE, activo INTEGER DEFAULT 1)")
    for col in ["orden","user_agent","referer","origin"]:
        try:
            if col=="orden": con.execute(f"ALTER TABLE canales ADD COLUMN {col} INTEGER DEFAULT 0")
            else: con.execute(f"ALTER TABLE canales ADD COLUMN {col} TEXT DEFAULT ''")
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
        r=redirect("/admin"); r.set_cookie("auth","ok", max_age=86400*30); return r
    return '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="background:#111;color:#fff;display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif"><form method="post" style="background:#222;padding:20px;border-radius:12px;width:320px"><h3>Login Panel</h3><input name="user" placeholder="Usuario" style="width:100%;padding:10px;margin:5px 0"><input name="pass" type="password" placeholder="Clave" style="width:100%;padding:10px"><button style="width:100%;padding:12px;background:#2a7ae2;color:#fff;border:0;border-radius:8px;margin-top:10px">Entrar</button></form></body></html>'

@app.route("/admin")
@app.route("/admin/")
def admin():
    if request.cookies.get("auth")!="ok": return redirect("/login")
    con=sqlite3.connect(DB)
    canales=con.execute("SELECT id,nombre,url,orden,user_agent,referer,origin FROM canales ORDER BY orden ASC").fetchall()
    total=len(canales)+1
    page=f'<html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta charset="utf-8"></head><body style="background:#111;color:#fff;font-family:sans-serif;padding:10px"><h2>Panel PRO v3 - {total-1} canales</h2><a href="/admin/users" style="color:#4fc3f7">USUARIOS</a> | <a href="/admin/logout" style="color:#f55">Salir</a><hr><form method="post" action="/add" style="background:#222;padding:15px;border-radius:12px;display:flex;gap:8px;flex-wrap:wrap;max-width:900px"><input name="nombre" placeholder="Nombre" required style="padding:10px;flex:1;min-width:120px"><input name="url" placeholder="https://...m3u8" required style="padding:10px;flex:2;min-width:200px"><input name="user_agent" placeholder="User-Agent (opcional)" style="padding:10px;flex:1;min-width:150px"><input name="referer" placeholder="Referer https://... (opcional)" style="padding:10px;flex:1;min-width:150px"><input name="origin" placeholder="Origin https://... (opcional)" style="padding:10px;flex:1;min-width:150px"><input name="posicion" type="number" min="1" max="{total}" placeholder="Pos #{total}" style="width:80px"><button style="padding:10px 20px;background:#2a7ae2;color:#fff;border:0;border-radius:8px">Agregar</button></form><hr><form method="post" action="/saveorder">'
    for i,c in enumerate(canales):
        ref_short = (c[5][:20] + '..') if c[5] and len(c[5])>20 else (c[5] or '')
        page+=f'<div style="background:#222;padding:12px;margin:8px 0;border-radius:10px;display:flex;gap:8px;align-items:center;flex-wrap:wrap"><input type="number" name="pos_{c[0]}" value="{i+1}" style="width:50px"><div style="flex:1;min-width:200px"><b>{i+1}. {c[1]}</b><br><small style="color:#aaa">{c[2][:50]}<br>Ref: {ref_short}</small></div><a href="/edit/{c[0]}" style="background:#2a7ae2;padding:8px 12px;border-radius:8px;color:#fff;text-decoration:none">EDIT</a><a href="/up/{c[0]}" style="background:#333;padding:8px 12px;border-radius:8px;color:#fff;text-decoration:none">▲</a><a href="/down/{c[0]}" style="background:#333;padding:8px 12px;border-radius:8px;color:#fff;text-decoration:none">▼</a><a href="/del/{c[0]}" style="background:#5a1a1a;padding:8px 12px;border-radius:8px;color:#ff7777;text-decoration:none">X</a></div>'
    page+='<button style="width:100%;padding:14px;background:#2a7ae2;color:#fff;border:0;border-radius:10px;margin-top:10px">GUARDAR ORDEN</button></form></body></html>'
    return page

@app.route("/admin/logout")
def logout():
    r=redirect("/login"); r.set_cookie("auth","", expires=0); return r

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
    n=request.form.get("nombre",""); u=request.form.get("url",""); ps=request.form.get("posicion","").strip()
    ua=request.form.get("user_agent","").strip(); ref=request.form.get("referer","").strip(); ori=request.form.get("origin","").strip()
    con=sqlite3.connect(DB); cs=con.execute("SELECT id,orden FROM canales ORDER BY orden").fetchall(); tot=len(cs); nv=tot
    if ps.isdigit():
        p=int(ps); nv=p-1
        for cid,ordn in cs:
            if ordn>=nv: con.execute("UPDATE canales SET orden=? WHERE id=?",(ordn+1,cid))
    con.execute("INSERT INTO canales (nombre,url,orden,user_agent,referer,origin) VALUES (?,?,?,?,?,?)",(n,u,nv,ua,ref,ori)); con.commit(); return redirect("/admin")

@app.route("/edit/<int:id>", methods=["GET","POST"])
def edit(id):
    con=sqlite3.connect(DB)
    if request.method=="POST":
        n=request.form.get("nombre",""); u=request.form.get("url","")
        ua=request.form.get("user_agent",""); ref=request.form.get("referer",""); ori=request.form.get("origin","")
        pos=request.form.get("orden","0")
        try: pos=int(pos)
        except: pos=0
        con.execute("UPDATE canales SET nombre=?,url=?,user_agent=?,referer=?,origin=?,orden=? WHERE id=?",(n,u,ua,ref,ori,pos,id)); con.commit(); con.close()
        return redirect("/admin")
    ch=con.execute("SELECT id,nombre,url,orden,user_agent,referer,origin FROM canales WHERE id=?",(id,)).fetchone()
    con.close()
    if not ch: return "No existe"
    return f'<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="background:#111;color:#fff;font-family:sans-serif;padding:15px"><h2>Editar {ch[1]}</h2><form method="post" style="background:#222;padding:15px;border-radius:12px;display:grid;gap:10px;max-width:600px"><input name="nombre" value="{ch[1]}" required style="padding:12px"><input name="url" value="{ch[2]}" required style="padding:12px"><input name="user_agent" value="{ch[4]}" placeholder="User-Agent" style="padding:12px"><input name="referer" value="{ch[5]}" placeholder="Referer" style="padding:12px"><input name="origin" value="{ch[6]}" placeholder="Origin" style="padding:12px"><input name="orden" type="number" value="{ch[3]}" style="padding:12px"><button style="padding:12px;background:#2a7ae2;color:#fff;border:0;border-radius:8px">GUARDAR</button></form><a href="/admin" style="color:#4fc3f7">Volver</a></body></html>'

@app.route("/del/<int:id>")
def dele(id):
    con=sqlite3.connect(DB); con.execute("DELETE FROM canales WHERE id=?",(id,)); con.commit(); return redirect("/admin")

@app.route("/admin/users")
@app.route("/admin/users/")
def users_page():
    if request.cookies.get("auth")!="ok": return redirect("/login")
    con=sqlite3.connect(DB); us=con.execute("SELECT id,user,pass,expira FROM usuarios ORDER BY id DESC").fetchall()
    h='<html><body style="background:#111;color:#fff;padding:15px;font-family:sans-serif"><a href="/admin" style="color:#4fc3f7">← Canales</a><h2>Usuarios</h2><form method="post" action="/adduser" style="background:#222;padding:10px;border-radius:10px"><input name="user" placeholder="Usuario" required><input name="pass" placeholder="Pass" required><input name="expira" type="date" required><button>CREAR</button></form><hr>'
    for x in us: h+=f'{x[1]} | {x[2]} | {x[3]} <a href="/deluser/{x[0]}" style="color:red">[X]</a><br>'
    return h+'</body></html>'

@app.route("/adduser", methods=["POST"])
def adduser():
    con=sqlite3.connect(DB); con.execute("INSERT INTO usuarios (user,pass,expira,activo) VALUES (?,?,?,1)",(request.form["user"],request.form["pass"],request.form["expira"])); con.commit(); return redirect("/admin/users")

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

# LIVE PROXY CON HEADERS + REWRITE HLS (FIX AMERICA TV / QAOTIC)
@app.route("/live/<username>/<password>/<path:stream>")
def live(username,password,stream):
    if not valid_user(username,password): return "Auth fail",403
    try: sid=int(stream.split(".")[0])
    except: sid=0
    con=sqlite3.connect(DB); ch=con.execute("SELECT url,user_agent,referer,origin FROM canales WHERE id=?",(sid,)).fetchone(); con.close()
    if not ch: return "No existe",404
    url, ua, ref, ori = ch[0] or "", ch[1] or "", ch[2] or "", ch[3] or ""
    headers={}
    headers["User-Agent"]=ua if ua.strip() else "Mozilla/5.0 (Linux; Android 13; SM-G998B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
    headers["Referer"]=ref if ref.strip() else "https://www.americatv.com.ar/"
    headers["Origin"]=ori if ori.strip() else headers["Referer"]
    headers["Accept"]="*/*"
    try:
        r=requests.get(url, headers=headers, timeout=15, verify=False, allow_redirects=True)
        text=r.text or ""
        if ".m3u8" in url.lower() or "#EXTM3U" in text:
            base=urllib.parse.urljoin(url, ".")
            out=[]
            for line in text.splitlines():
                s=line.strip()
                if not s or s.startswith("#"): out.append(s)
                else:
                    seg=urllib.parse.urljoin(base, s)
                    prox=f"/hls/{sid}?u="+urllib.parse.quote_plus(seg)
                    out.append(prox)
            return Response("\n".join(out), content_type="application/vnd.apple.mpegurl", headers={"Access-Control-Allow-Origin":"*"})
        return Response(r.content, status=r.status_code, content_type=r.headers.get('Content-Type','video/mp2t'))
    except Exception as e:
        return f"Error proxy {e}", 502

@app.route("/hls/<int:sid>")
def hls_proxy(sid):
    u=request.args.get("u","")
    if not u: return "no url",400
    con=sqlite3.connect(DB); ch=con.execute("SELECT user_agent,referer,origin FROM canales WHERE id=?",(sid,)).fetchone(); con.close()
    ua, ref, ori = (ch[0] if ch else ""), (ch[1] if ch else ""), (ch[2] if ch else "")
    headers={}
    headers["User-Agent"]=ua if ua and ua.strip() else "Mozilla/5.0 (Linux; Android 13; SM-G998B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36"
    headers["Referer"]=ref if ref and ref.strip() else "https://www.americatv.com.ar/"
    headers["Origin"]=ori if ori and ori.strip() else headers["Referer"]
    try:
        r=requests.get(u, headers=headers, stream=True, timeout=20, verify=False)
        return Response(r.iter_content(chunk_size=8192), status=r.status_code, content_type=r.headers.get('Content-Type','video/mp2t'), headers={"Access-Control-Allow-Origin":"*"})
    except Exception as e:
        return f"Error hls {e}",502

@app.route("/xmltv.php")
def xmltv(): return Response("<tv></tv>", mimetype='text/xml')
@app.route("/")
def index(): return redirect("/admin")
app.run(host='0.0.0.0',port=80)
PY

sed -i "s/__ADMIN_USER__/$ADMIN_USER/g; s/__ADMIN_PASS__/$ADMIN_PASS/g" /root/panel/app.py

cat > /etc/systemd/system/panel.service << SERVICE
[Unit]
Description=Panel IPTV Gusty v3 PRO
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

# Comandos utiles
cat > /usr/local/bin/panel-actualizar << 'UPD'
#!/bin/bash
cd /root/panel
FECHA=$(date +%Y-%m-%d_%H-%M)
cp app.py /root/backups-panel/app.py_PRE_UPDATE_$FECHA.py 2>/dev/null || true
curl -k -L -o app.py https://raw.githubusercontent.com/gusty0018/panel-iptv/main/app.py
python3 -m py_compile app.py && systemctl restart panel && echo "PANEL ACTUALIZADO $FECHA"
UPD
chmod +x /usr/local/bin/panel-actualizar

IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
echo ""
echo "========================================"
echo " PANEL v3 PRO INSTALADO"
echo " URL: http://$IP/admin"
echo " User: $ADMIN_USER"
echo " Pass: $ADMIN_PASS"
echo " Fix + Referer OK"
echo " Comando: panel-actualizar"
echo "========================================"