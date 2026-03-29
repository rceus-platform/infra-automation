#!/bin/bash
set -e

# ========================
# CONFIG
# ========================
BASE_DIR="/opt/apps"
DOMAIN_BASE="rceus.duckdns.org"
DUCKDNS_TOKEN_FILE="/etc/letsencrypt/duckdns.ini"

NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

# ========================
# INPUT
# ========================
REPO_NAME="$1"

if [ -z "$REPO_NAME" ]; then
  echo "Usage: sudo ./delete_app.sh <github-repo-name>"
  exit 1
fi

# ========================
# DERIVED VALUES
# ========================
APP_NAME="$REPO_NAME"
APP_DIR="$BASE_DIR/$APP_NAME"
SERVICE_NAME="$APP_NAME.service"

SUBDOMAIN_NAME="${REPO_NAME#*-}"
DOMAIN="$SUBDOMAIN_NAME.$DOMAIN_BASE"

NGINX_CONF_NAME="$DOMAIN"

echo "===================================="
echo "Repo       : $REPO_NAME"
echo "App dir    : $APP_DIR"
echo "Service    : $SERVICE_NAME"
echo "Domain     : $DOMAIN"
echo "===================================="

# ========================
# 1. Stop & remove systemd service
# ========================
if systemctl list-unit-files | grep -q "^$SERVICE_NAME"; then
  systemctl stop "$APP_NAME" || true
  systemctl disable "$APP_NAME" || true
  rm -f "/etc/systemd/system/$SERVICE_NAME"
  systemctl daemon-reload
fi

# ========================
# 2. Remove nginx config (DOMAIN-BASED)
# ========================
rm -f "$NGINX_SITES_ENABLED/$NGINX_CONF_NAME"
rm -f "$NGINX_SITES_AVAILABLE/$NGINX_CONF_NAME"

nginx -t
systemctl reload nginx

# ========================
# 3. Remove DuckDNS record
# ========================
TOKEN=$(grep -E '^dns_duckdns_token' "$DUCKDNS_TOKEN_FILE" | cut -d= -f2 | tr -d ' ')
curl -s "https://www.duckdns.org/update?domains=$SUBDOMAIN_NAME&token=$TOKEN&clear=true"

# ========================
# 4. Remove app directory
# ========================
rm -rf "$APP_DIR"

echo "===================================="
echo "🗑️  App deleted successfully"
echo "❌ Removed: $DOMAIN"
echo "===================================="