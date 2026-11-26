#!/usr/bin/env bash
# Pasang dan jalankan aplikasi Flask sebagai service systemd di EC2 (Amazon Linux 2023).
#   ./scripts/setup-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$HOME/.config/facility-ticketing/db.env"
VENV="$ROOT/.venv"
[ -f "$ENV_FILE" ] || { echo "Tidak ada $ENV_FILE. Jalankan provision-rds.sh dulu."; exit 1; }

echo "==> Paket sistem"
sudo dnf install -y -q python3-pip mariadb105 >/dev/null 2>&1 || true

echo "==> Virtualenv + dependensi"
python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q -r "$ROOT/app/requirements.txt"

echo "==> Uji koneksi EC2 -> RDS dan buat tabel"
set -a; source "$ENV_FILE"; set +a
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" -e \
  "SELECT 'koneksi OK' AS status, VERSION() AS mysql_version, @@hostname AS db_host;" "$DB_NAME"
( cd "$ROOT/app" && "$VENV/bin/python" -c "import app; app.init_schema(); print('Tabel tickets siap')" )

echo "==> Service systemd facility-ticketing (gunicorn :8080)"
sudo tee /etc/systemd/system/facility-ticketing.service >/dev/null <<EOF
[Unit]
Description=Facility Ticketing (Flask + gunicorn)
After=network-online.target

[Service]
User=$(whoami)
WorkingDirectory=$ROOT/app
EnvironmentFile=$ENV_FILE
ExecStart=$VENV/bin/gunicorn --workers 2 --bind 0.0.0.0:8080 --access-logfile - app:app
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now facility-ticketing
sleep 2
sudo systemctl --no-pager --lines=5 status facility-ticketing | head -12
echo
curl -s http://localhost:8080/health; echo
