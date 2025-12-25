Below is **clean, end-to-end documentation** for recreating **this entire system from scratch** on a fresh Ubuntu VM.

This is written so that **future-you** (or anyone else) can follow it without guessing.

No fluff. No shortcuts. No missing steps.

---

# 🚀 FastAPI Multi-App Platform on a Single VM

**(GitHub → systemd → nginx → DuckDNS)**

---

## 0️⃣ What this system gives you

* One Ubuntu VM (Oracle / AWS / any cloud)
* Unlimited FastAPI apps
* Each app:

  * Own GitHub repo
  * Own systemd service
  * Own internal port
  * Own subdomain (`app-name.yourdomain`)
* Reverse-proxied via nginx
* One script to:

  * create apps
  * deploy
  * delete apps
* Zero manual nginx editing per app

---

## 1️⃣ VM prerequisites (do once)

### OS

* Ubuntu 20.04+ (tested)

### Packages

```bash
sudo apt update
sudo apt install -y \
  git curl nginx python3 python3-venv \
  build-essential
```

Enable nginx:

```bash
sudo systemctl enable nginx
sudo systemctl start nginx
```

---

## 2️⃣ Networking (critical)

### Open ports

* 22 (SSH)
* 80 (HTTP)

On Oracle / AWS:

* Open **Security List / Security Group**
* Allow `0.0.0.0/0 → TCP 80`

### Linux firewall (if used)

```bash
sudo iptables -P INPUT ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
```

---

## 3️⃣ DNS (DuckDNS – free domain)

1. Create account → [https://duckdns.org](https://duckdns.org)
2. Create base domain:

   ```
   rceus.duckdns.org
   ```
3. Save token **once** on VM:

```bash
sudo mkdir -p /etc/letsencrypt
sudo nano /etc/letsencrypt/duckdns.ini
```

Contents:

```ini
dns_duckdns_token = YOUR_DUCKDNS_TOKEN
```

Permissions:

```bash
sudo chmod 600 /etc/letsencrypt/duckdns.ini
```

---

## 4️⃣ Directory layout (fixed standard)

```text
/opt
├── apps/           # All FastAPI apps live here
│   └── <app-name>/
│       ├── .venv/
│       ├── run.sh
│       └── source code
└── automation/
    ├── create_app.sh
    └── delete_app.sh
```

Create base dirs:

```bash
sudo mkdir -p /opt/apps /opt/automation
sudo chown -R ubuntu:ubuntu /opt/apps /opt/automation
```

---

## 5️⃣ GitHub organization (recommended)

Create an **organization**, e.g.:

```
rceus-platform
```

All app repos live here:

```
https://github.com/rceus-platform/<repo>
```

Example repo:

```
python-fastapi-template
```

---

## 6️⃣ FastAPI repo contract (important)

Every FastAPI repo **must follow this minimum contract**:

### Required files

```
requirements.txt
src/app/main.py
```

### `main.py`

```python
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def root():
    return {"message": "FastAPI app is running"}

@app.get("/health")
def health():
    return {"status": "ok"}
```

### `requirements.txt`

```
fastapi
uvicorn
```

---

## 7️⃣ create_app.sh (single source of truth)

Create file:

```bash
sudo nano /opt/automation/create_app.sh
```

Paste **entire file**:

```bash
#!/bin/bash
set -e

BASE_DIR="/opt/apps"
GITHUB_ORG="rceus-platform"
DOMAIN_BASE="rceus.duckdns.org"
DUCKDNS_TOKEN_FILE="/etc/letsencrypt/duckdns.ini"

NGINX_AVAIL="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"

REPO_NAME="$1"
PORT="$2"

if [ -z "$REPO_NAME" ] || [ -z "$PORT" ]; then
  echo "Usage: sudo create_app.sh <github-repo-name> <port>"
  exit 1
fi

APP_NAME="$REPO_NAME"
APP_DIR="$BASE_DIR/$APP_NAME"
SERVICE_NAME="$APP_NAME.service"

SUBDOMAIN="${REPO_NAME#*-}"
DOMAIN="$SUBDOMAIN.$DOMAIN_BASE"

REPO_URL="https://github.com/$GITHUB_ORG/$REPO_NAME.git"

echo "Creating app:"
echo " Repo      : $REPO_NAME"
echo " Domain    : $DOMAIN"
echo " Port      : $PORT"
echo " Directory : $APP_DIR"

mkdir -p "$APP_DIR"
git clone "$REPO_URL" "$APP_DIR"

python3 -m venv "$APP_DIR/.venv"
"$APP_DIR/.venv/bin/pip" install -r "$APP_DIR/requirements.txt"

cat > "$APP_DIR/run.sh" <<EOF
#!/bin/bash
exec $APP_DIR/.venv/bin/uvicorn src.app.main:app --host 127.0.0.1 --port $PORT
EOF

chmod +x "$APP_DIR/run.sh"

cat > "/etc/systemd/system/$SERVICE_NAME" <<EOF
[Unit]
Description=$APP_NAME FastAPI App
After=network.target

[Service]
User=ubuntu
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/run.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$APP_NAME"
systemctl start "$APP_NAME"

cat > "$NGINX_AVAIL/$APP_NAME" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf "$NGINX_AVAIL/$APP_NAME" "$NGINX_ENABLED/$APP_NAME"
nginx -t && systemctl reload nginx

TOKEN=$(grep dns_duckdns_token "$DUCKDNS_TOKEN_FILE" | cut -d= -f2 | tr -d ' ')
curl -s "https://www.duckdns.org/update?domains=$SUBDOMAIN&token=$TOKEN&ip="

echo "✅ App available at http://$DOMAIN"
```

Make executable:

```bash
sudo chmod +x /opt/automation/create_app.sh
```

---

## 8️⃣ delete_app.sh (safe cleanup)

```bash
sudo nano /opt/automation/delete_app.sh
```

```bash
#!/bin/bash
APP="$1"

if [ -z "$APP" ]; then
  echo "Usage: delete_app.sh <app-name>"
  exit 1
fi

systemctl stop "$APP" || true
systemctl disable "$APP" || true
rm -f "/etc/systemd/system/$APP.service"

rm -f "/etc/nginx/sites-enabled/$APP"
rm -f "/etc/nginx/sites-available/$APP"

rm -rf "/opt/apps/$APP"

systemctl daemon-reload
nginx -t && systemctl reload nginx

echo "🗑️ $APP deleted"
```

```bash
sudo chmod +x /opt/automation/delete_app.sh
```

---

## 9️⃣ Create an app (one command)

```bash
sudo /opt/automation/create_app.sh python-fastapi-template 8002
```

Result:

```
http://fastapi-template.rceus.duckdns.org
```

---

## 🔟 Debug checklist (when something breaks)

### App running?

```bash
sudo systemctl status <app-name>
```

### Port listening?

```bash
sudo ss -lntp | grep <port>
```

### nginx conflicts?

```bash
sudo nginx -T | grep conflicting
```

### Duplicate server_name?

```bash
grep -R "<domain>" /etc/nginx/sites-enabled
```

---

## 🔐 Security notes (later upgrades)

* Add HTTPS (self-signed or certbot)
* Add rate-limiting in nginx
* Add UFW once stable
* Add CI auto-deploy (GitHub Actions → SSH)

---

## 🧠 Mental model (remember this)

```
Internet
  ↓
nginx (port 80)
  ↓
127.0.0.1:<unique port>
  ↓
FastAPI (systemd)
```

Everything else is automation.

---

# 🚀 FastAPI VM Platform

**Multi-App Deployment with Nginx, systemd, DuckDNS & CI/CD**

This repository provides a **production-grade platform** to deploy **multiple FastAPI applications on a single Ubuntu VM**, each with:

* Its own GitHub repository
* Its own systemd service
* Its own internal port
* Its own subdomain
* Zero manual nginx editing
* Optional HTTPS
* Automated deployment on `git push`

---

## 🧱 Architecture Overview

```
Internet
   ↓
Nginx (80 / 443)
   ↓
127.0.0.1:<port>
   ↓
FastAPI (systemd service)
```

Each app is isolated by:

* Port
* Service
* Repo
* Subdomain

---

## 📁 Directory Structure

```
/opt
├── apps/
│   ├── <app-name>/
│   │   ├── .venv/
│   │   ├── run.sh
│   │   └── source code
│   └── ...
└── automation/
    ├── create_app.sh
    ├── delete_app.sh
    └── deploy_app.sh
```

---

## 🛠️ VM Prerequisites (One-Time)

### OS

* Ubuntu 20.04+

### Install packages

```bash
sudo apt update
sudo apt install -y git curl nginx python3 python3-venv
```

Enable nginx:

```bash
sudo systemctl enable nginx
sudo systemctl start nginx
```

---

## 🌐 DNS (DuckDNS – Free)

1. Create account → [https://duckdns.org](https://duckdns.org)
2. Create base domain:

   ```
   rceus.duckdns.org
   ```
3. Store token securely on VM:

```bash
sudo mkdir -p /etc/letsencrypt
sudo nano /etc/letsencrypt/duckdns.ini
```

```ini
dns_duckdns_token = YOUR_DUCKDNS_TOKEN
```

```bash
sudo chmod 600 /etc/letsencrypt/duckdns.ini
```

---

## 🏗️ FastAPI Repo Contract (Required)

Every FastAPI repo **must follow this minimal contract**.

### Required files

```
requirements.txt
src/app/main.py
```

### `main.py`

```python
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def root():
    return {"message": "FastAPI app is running"}

@app.get("/health")
def health():
    return {"status": "ok"}
```

### `requirements.txt`

```
fastapi
uvicorn
```

---

## ⚙️ Automation Scripts

### `create_app.sh`

Creates:

* App directory
* Python venv
* systemd service
* nginx config
* DuckDNS subdomain

Usage:

```bash
sudo ./create_app.sh python-fastapi-template 8002
```

Result:

```
http://fastapi-template.rceus.duckdns.org
```

---

### `delete_app.sh`

Removes:

* systemd service
* nginx config
* app directory

Usage:

```bash
sudo ./delete_app.sh python-fastapi-template
```

---

## 🔄 CI Auto-Deploy (Push → Live)

### How it works

* GitHub Actions runs on **push to `main`**
* SSHs into VM
* Pulls latest code
* Restarts systemd service

### Requirements

On VM:

* SSH key added for GitHub Actions
* Apps already created via `create_app.sh`

---

### `.github/workflows/deploy.yml` (Per App Repo)

```yaml
name: Deploy FastAPI App

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Deploy over SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.VM_HOST }}
          username: ubuntu
          key: ${{ secrets.VM_SSH_KEY }}
          script: |
            cd /opt/apps/python-fastapi-template
            git pull origin main
            sudo systemctl restart python-fastapi-template
```

### Required Secrets (Repo → Settings → Secrets)

| Name       | Value           |
| ---------- | --------------- |
| VM_HOST    | VM public IP    |
| VM_SSH_KEY | private SSH key |

> ⚠️ Secrets are per-repo by design (GitHub security model)

---

## 🔐 HTTPS / SSL (Production-Ready)

### Install certbot (snap)

```bash
sudo snap install core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
```

---

### Issue SSL for an app

```bash
sudo certbot --nginx -d fastapi-template.rceus.duckdns.org
```

Certbot will:

* Validate domain
* Update nginx config
* Enable HTTPS
* Auto-renew certificates

Verify:

```bash
https://fastapi-template.rceus.duckdns.org/health
```

---

## 🔄 SSL Auto-Renew (Built-In)

Certbot installs:

```bash
systemctl list-timers | grep certbot
```

No manual renewal needed.

---

## 🧪 Debug Checklist

### App running?

```bash
sudo systemctl status <app-name>
```

### Port listening?

```bash
sudo ss -lntp | grep <port>
```

### nginx conflicts?

```bash
sudo nginx -T | grep conflicting
```

### Duplicate server_name?

```bash
grep -R "<domain>" /etc/nginx/sites-enabled
```

---

## 🧠 Design Rules (Important)

* ❌ Never manually create nginx configs
* ✅ Always use `create_app.sh`
* ❌ Never reuse ports
* ✅ One repo = one service = one nginx file
* ❌ No dots in nginx filenames
* ✅ `server_name` controls routing, not filename

---

## 🚀 What This Platform Enables

* Unlimited FastAPI apps on one VM
* Zero-touch deployments
* Clean isolation
* Production-grade routing
* HTTPS
* Easy teardown

---

## 🧩 Future Enhancements (Optional)

* HTTP → HTTPS redirect everywhere
* Rate limiting
* Basic auth per app
* Blue-green deployments
* Docker support
* Monitoring (Prometheus / Grafana)

---

## 📌 TL;DR

```bash
# Create app
sudo ./create_app.sh python-fastapi-template 8002

# Push code → live automatically
git push origin main

# Secure with HTTPS
sudo certbot --nginx -d fastapi-template.rceus.duckdns.org
```

---

## 🏁 Status

This platform is **production-ready**, **scalable**, and **fully automated**.

You now own a **self-hosted PaaS**.
