#!/bin/bash

set -e  # Script bei Fehler beenden

echo "========================================="
echo "RaceResult RFID Middleware - Setup"
echo "========================================="

# Schritt 1: System Update
echo "📦 Update System..."
sudo apt update
sudo apt upgrade -y
sudo apt install -y python3-pip sqlite3 nginx curl git build-essential python3-dev dphys-swapfile

# Schritt 2: Swap erhöhen
echo "💾 Konfiguriere Swap..."
#sudo dphys-swapfile swapoff 2>/dev/null || true
#sudo sed -i 's/CONF_SWAPSIZE=100/CONF_SWAPSIZE=512/g' /etc/dphys-swapfile
#sudo dphys-swapfile setup
#sudo dphys-swapfile swapon

echo "🔄 Starte rpi-swap Konfiguration..."

# SWAP Installation
if ! command -v rpi-swap &> /dev/null; then
    echo "📦 Installiere rpi-swap..."
    sudo apt-get update
    sudo apt-get install -y rpi-swap
else
    echo "✅ rpi-swap bereits installiert"
fi

# SWAP: Aktuellen Swap deaktivieren (falls vorhanden)
echo "⏹️  Deaktiviere aktuellen Swap..."
sudo rpi-swap off 2>/dev/null || true

# SWAP: Swap-Größe auf 512 MB setzen
echo "⚙️  Setze Swap-Größe auf 512 MB..."
sudo rpi-swap set 512

# SWAP: Swap aktivieren
echo "▶️  Aktiviere Swap..."
sudo rpi-swap on

# SWAP: Status anzeigen
echo "📊 Swap-Status:"
sudo rpi-swap status

echo "✅ rpi-swap Konfiguration abgeschlossen!"

# Schritt 3: Projektverzeichnis
echo "📁 Erstelle Verzeichnisse..."
cd ~
mkdir -p raceresult-middleware
cd raceresult-middleware
mkdir -p {app,config,www,logs,data,backup}

# Schritt 4: Alle Dateien herunterladen oder erstellen
echo "📥 Generiere Dateien..."
# Hier würden die Dateien kopiert ode erstellt
# Soweit möglich, werden alle Dateien im Skript create_files.sh erstellt

. ./create_files.sh

# Installieren
pip install --upgrade pip setuptools wheel
pip install -r requirements.txt


# Schritt 5: Python Environment
#echo "🐍 Richte Python Environment ein..."
#python3 -m venv venv
#source venv/bin/activate
#pip install --upgrade pip setuptools wheel
#pip install -r requirements.txt

# Schritt 5: Systemd Service
echo "⚙️  Installiere systemd Service..."
sudo cp /etc/systemd/system/raceresult-middleware.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable raceresult-middleware.service

# Schritt 6: Nginx
echo "🌐 Konfiguriere Nginx..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo cp nginx/nginx.conf /etc/nginx/sites-available/raceresult
sudo ln -sf /etc/nginx/sites-available/raceresult /etc/nginx/sites-enabled/
sudo ln -sf ~/raceresult-middleware/www /var/www/raceresult
sudo nginx -t
sudo systemctl restart nginx

# Schritt 7: Berechtigungen
echo "🔐 Setze Berechtigungen..."
chmod 755 ~/raceresult-middleware
chmod 755 ~/raceresult-middleware/data
chmod 755 ~/raceresult-middleware/logs
chmod 600 ~/raceresult-middleware/.env
chmod 600 ~/raceresult-middleware/config/config.json


# Schritt 8 Datenbankarchivierung einrichten

# Define the cron job (schedule + command)
CRON_JOB="0 0 1 * * ~/raceresult-middleware/archive-old-data.sh"
 
# Check if the cron job exists
if ! crontab -l | grep -qF "$CRON_JOB"; then
  echo "Adding cron job: $CRON_JOB"
  
  # Create a temporary crontab file
  TEMP_CRONTAB=$(mktemp)
  
  # Copy existing crontab (suppress error if no crontab exists)
  crontab -l > "$TEMP_CRONTAB" 2>/dev/null
  
  # Append the new job
  echo "$CRON_JOB" >> "$TEMP_CRONTAB"
  
  # Load the updated crontab
  crontab "$TEMP_CRONTAB"
  
  # Cleanup
  rm -f "$TEMP_CRONTAB"
  
  echo "Archivierungsjob erstellt!"
else
  echo "Archivierungsjob bereits vorhanden! Nothing to do."
fi

chmod +x ~/raceresult-middleware/archive-old-data.sh


# Schritt 9: Starten
echo "🚀 Starte Services..."
sudo systemctl start raceresult-middleware
sudo systemctl restart nginx

# Schritt 10: Status prüfen
echo ""
echo "========================================="
echo "✅ Installation abgeschlossen!"
echo "========================================="
echo ""
echo "📊 Dashboard: http://raspberrypi.local"
echo "🔍 Logs: journalctl -u raceresult-middleware -f"
echo "📈 Status: sudo systemctl status raceresult-middleware"
echo ""
