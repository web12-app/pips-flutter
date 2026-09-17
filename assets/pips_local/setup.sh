#!/bin/sh
# Pips local you-get server — one-time setup, run INSIDE ReTerminal's Alpine
# session, right after fetching the two files from the Pips app:
#
#   wget -O /tmp/pips_yg_server.py http://127.0.0.1:8788/server.py
#   wget -O /tmp/pips-yg-setup.sh  http://127.0.0.1:8788/setup.sh
#   sh /tmp/pips-yg-setup.sh
#
# Optional owner cookies (explicit file only — never a browser/app database):
#   PIPS_YG_COOKIES=/path/to/cookies.txt sh /tmp/pips-yg-setup.sh
set -e

echo "[1/5] installing python3 + ffmpeg (Alpine packages)…"
apk add --no-cache python3 py-pip ffmpeg >/dev/null

echo "[2/5] installing you-get + dukpy…"
pip3 install --quiet you-get dukpy

echo "[3/5] placing the server in ~/.pips …"
mkdir -p ~/.pips
cp /tmp/pips_yg_server.py ~/.pips/pips_yg_server.py

echo "[4/5] starting the server in the background…"
pkill -f pips_yg_server.py 2>/dev/null || true
nohup env PIPS_YG_COOKIES="${PIPS_YG_COOKIES:-}" python3 ~/.pips/pips_yg_server.py \
  > ~/.pips/server.log 2>&1 &
sleep 1

echo "[5/5] health check…"
python3 -c "import json,urllib.request;print(json.load(urllib.request.urlopen('http://127.0.0.1:8787/health',timeout=8)))"

echo ""
echo "Pips local you-get server is running at http://127.0.0.1:8787"
echo ""
echo "Notes:"
echo " - keep this ReTerminal session (or the app in the background) alive;"
echo "   the server lives as long as it does. Re-run this script to restart it."
echo " - logs: tail -f ~/.pips/server.log"
echo " - stop: pkill -f pips_yg_server.py"
