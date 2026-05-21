###################################
# Environment einrichten #
###################################

cat > ~/raceresult-middleware/.env << 'EOF'

RACERESULT_API_URL=https://api.raceresult.com
RACERESULT_API_KEY=&ENdk4fA+FGI9nbG(Sb7j6twJKuVCVl2ysr(F&p?&ODdpAHZPNQoNPK7JO()6Xex
RACERESULT_EVENT_ID=370304
MIDDLEWARE_PORT=5000
LOG_LEVEL=info
EOF

######################
# Config JSON        #
######################

cat > config/config.json << 'EOF'
{
  "readers": [
    {
      "id": "Reader1",
      "host": "192.168.178.111",
      "port": 4001
#    },
#    {
#      "id": "Reader2",
#      "host": "192.168.178.112",
#      "port": 4001
    }
  ],
  "raceresult": {
    "api_url": "$RACERESULT_API_URL",
    "api_key": "$RACERESULT_API_KEY",
    "event_id": "$RACERESULT_EVENT_ID"
  },
  "database": {
    "path": "/home/pi/raceresult-middleware/data/timing_data.db",
    "max_buffer": 5000
  }
}
EOF


#######################################
# Datenbank Archivierungsskript bauen #
#######################################

cat > ~/raceresult-middleware/archive-old-data.sh << 'EOF'
#!/bin/bash
cd ~/raceresult-middleware

# 30 Tage alte Daten in separate Datei exportieren
sqlite3 data/timing_data.db << SQL
.mode csv
.output data/archive-$(date +%Y%m).csv
SELECT * FROM rfid_reads 
WHERE datetime(timestamp) < datetime('now', '-30 days');
SQL

# Gelöschte Daten entfernen
sqlite3 data/timing_data.db << SQL
DELETE FROM rfid_reads 
WHERE datetime(timestamp) < datetime('now', '-30 days');
PRAGMA vacuum;
SQL
EOF


#########################################
# Definition der Logrotation einrichten #
#########################################
sudo cat > /etc/logrotate.d/raceresult << 'EOF'
/home/pi/raceresult-middleware/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 pi pi
    sharedscripts
}
EOF


###############################
# Nginx-Definition einrichten #
###############################

sudo cat > ~/raceresult-middleware/nginx/nginx.conf << 'EOF'

upstream raceresult_backend {
    server 127.0.0.1:5000;
    keepalive 32;
}

events {
    worker_connections 256;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    keepalive_timeout 30;
    client_max_body_size 1M;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript;
    gzip_disable "msie6";

    server {
    	listen 80 default_server;
    	listen [::]:80 default_server;
    	server_name _;

   	 # Performance für Pi3
   	 worker_connections 256;
   	 client_max_body_size 1M;
   	 keepalive_timeout 30;
    
        #root /usr/share/nginx/html;
        #index index.html;

        root /var/www/raceresult;
        index index.html;

   # Dashboard
        location / {
            try_files $uri /index.html;
        }

   # API Proxy
        location /api/ {
   	    proxy_pass http://raceresult_backend;
            proxy_http_version 1.1;
       	    proxy_set_header Connection "";
       	    proxy_set_header Host $host;
       	    proxy_set_header X-Real-IP $remote_addr;
       	    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            # Timeouts
            proxy_connect_timeout 10s;
            proxy_send_timeout 10s;
            proxy_read_timeout 10s;
        }

    # Health Check
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
    }

    # Metrics
        location /metrics {
            proxy_pass http://raceresult_backend/api/metrics;
            access_log off;
        }
    }
}
EOF


######################
# Middleware Service #
######################

sudo cat > /etc/systemd/system/raceresult-middleware.service << 'EOF'

[Unit]
Description=RaceResult RFID Middleware
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/raceresult-middleware
#Environment="PATH=/home/pi/raceresult-middleware"
ExecStart=/home/pi/raceresult-middleware/app/main.py

# Restart Policy
Restart=always
RestartSec=10

# Resource Limits (Pi3 freundlich)
MemoryLimit=256M
CPUQuota=150%

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=raceresult

[Install]
WantedBy=multi-user.target

EOF


############################
# Index.html ==> DAshboard #
############################

sudo cat > ~/raceresult-middleware/www/index.html << 'EOF'

<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RaceResult RFID Monitor</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, sans-serif;
            background: #1a1a1a;
            color: #fff;
            padding: 20px;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1000px;
            margin: 0 auto;
        }
        
        header {
            text-align: center;
            margin-bottom: 30px;
            border-bottom: 3px solid #00a86b;
            padding-bottom: 20px;
        }
        
        h1 {
            font-size: 28px;
            color: #00a86b;
            margin-bottom: 5px;
        }
        
        header p {
            color: #888;
            font-size: 14px;
        }
        
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        
        .status-card {
            background: #2a2a2a;
            border: 2px solid #00a86b;
            border-radius: 8px;
            padding: 20px;
            text-align: center;
            transition: all 0.3s;
        }
        
        .status-card:hover {
            border-color: #00ff99;
            box-shadow: 0 0 10px rgba(0, 168, 107, 0.3);
        }
        
        .status-card h3 {
            color: #00a86b;
            margin-bottom: 10px;
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .status-value {
            font-size: 36px;
            font-weight: bold;
            margin: 10px 0;
            min-height: 45px;
        }
        
        .status-ok {
            color: #00a86b;
        }
        
        .status-warning {
            color: #ff9500;
        }
        
        .status-error {
            color: #ff4444;
        }
        
        .status-subtitle {
            font-size: 12px;
            color: #666;
        }
        
        .section-title {
            color: #00a86b;
            margin: 25px 0 15px 0;
            padding-bottom: 10px;
            border-bottom: 1px solid #333;
            font-size: 16px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .readers-container {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        
        .reader-card {
            background: #2a2a2a;
            border: 1px solid #00a86b;
            border-radius: 8px;
            padding: 15px;
        }
        
        .reader-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 12px;
        }
        
        .reader-name {
            font-weight: bold;
            color: #fff;
            font-size: 14px;
        }
        
        .reader-badge {
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: bold;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .badge-connected {
            background: #00a86b;
            color: #1a1a1a;
        }
        
        .badge-disconnected {
            background: #ff4444;
            color: #fff;
        }
        
        .reader-info {
            font-size: 12px;
            color: #888;
            margin: 8px 0;
        }
        
        .reader-info strong {
            color: #00a86b;
        }
        
        .reads-log {
            background: #2a2a2a;
            border: 1px solid #00a86b;
            border-radius: 8px;
            padding: 15px;
            max-height: 400px;
            overflow-y: auto;
        }
        
        .read-entry {
            background: #1a1a1a;
            padding: 10px;
            margin-bottom: 8px;
            border-left: 3px solid #00a86b;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            border-radius: 2px;
        }
        
        .read-time {
            color: #00a86b;
            font-weight: bold;
            display: inline-block;
            min-width: 80px;
        }
        
        .read-reader {
            color: #ff9500;
            margin: 0 10px;
        }
        
        .read-tag {
            color: #fff;
            word-break: break-all;
        }
        
        .empty-state {
            text-align: center;
            padding: 20px;
            color: #666;
        }
        
        .last-update {
            text-align: center;
            font-size: 11px;
            color: #555;
            margin-top: 30px;
            padding-top: 15px;
            border-top: 1px solid #333;
        }
        
        .loading {
            opacity: 0.5;
            animation: pulse 1s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        .spinner {
            display: inline-block;
            animation: spin 1s linear infinite;
        }
        
        @media (max-width: 600px) {
            .status-grid {
                grid-template-columns: repeat(2, 1fr);
            }
            
            h1 {
                font-size: 20px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>⏱️ RaceResult RFID Monitor</h1>
            <p>Raspberry Pi 3 - Live Status</p>
        </header>
        
        <div class="status-grid">
            <div class="status-card">
                <h3>System Status</h3>
                <div class="status-value" id="system-status">⏳</div>
                <div class="status-subtitle" id="system-text">Wird geladen...</div>
            </div>
            
            <div class="status-card">
                <h3>API Verbindung</h3>
                <div class="status-value" id="api-status">⏳</div>
                <div class="status-subtitle" id="api-text">Wird überprüft...</div>
            </div>
            
            <div class="status-card">
                <h3>Gepufferte Reads</h3>
                <div class="status-value" id="buffer-count">0</div>
                <div class="status-subtitle">Warten auf Sync</div>
            </div>
            
            <div class="status-card">
                <h3>Reads Heute</h3>
                <div class="status-value" id="total-reads">0</div>
                <div class="status-subtitle">Erfasst</div>
            </div>
        </div>
        
        <div class="section-title">📡 Reader Status</div>
        <div class="readers-container" id="readers-container">
            <div class="empty-state">🔄 Wird geladen...</div>
        </div>
        
        <div class="section-title">📋 Letzte RFID-Reads</div>
        <div class="reads-log">
            <div id="reads-log">
                <div class="empty-state">⏳ Wartet auf RFID-Daten...</div>
            </div>
        </div>
        
        <div class="last-update">
            Aktualisiert: <span id="last-update">-</span> | Auto-Refresh: 2 Sekunden
        </div>
    </div>
    
    <script>
        const API_BASE = '/api';
        
        async function fetchStatus() {
            try {
                const response = await fetch(`${API_BASE}/status`);
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                
                const data = await response.json();
                
                updateSystemStatus(data);
                updateReaderStatus(data.readers);
                updateReadsCounts(data);
                updateLastUpdate();
                
            } catch (error) {
                console.error('Fehler beim Abrufen des Status:', error);
                updateErrorState();
            }
        }
        
        function updateSystemStatus(data) {
            const systemStatus = document.getElementById('system-status');
            const systemText = document.getElementById('system-text');
            const apiStatus = document.getElementById('api-status');
            const apiText = document.getElementById('api-text');
            
            // System Status
            if (data.system_healthy) {
                systemStatus.textContent = '✅';
                systemStatus.className = 'status-value status-ok';
                systemText.textContent = 'Online';
            } else {
                systemStatus.textContent = '⚠️';
                systemStatus.className = 'status-value status-warning';
                systemText.textContent = 'Probleme erkannt';
            }
            
            // API Status
            if (data.api_configured && data.api_connected) {
                apiStatus.textContent = '✅';
                apiStatus.className = 'status-value status-ok';
                apiText.textContent = 'Verbunden';
            } else {
                apiStatus.textContent = '❌';
                apiStatus.className = 'status-value status-error';
                apiText.textContent = 'Nicht verbunden';
            }
        }
        
        function updateReaderStatus(readers) {
            const container = document.getElementById('readers-container');
            container.innerHTML = '';
            
            if (!readers || readers.length === 0) {
                container.innerHTML = '<div class="empty-state">Keine Reader konfiguriert</div>';
                return;
            }
            
            readers.forEach(reader => {
                const card = document.createElement('div');
                card.className = 'reader-card';
                
                const badge = reader.connected ?
                    '<span class="reader-badge badge-connected">VERBUNDEN</span>' :
                    '<span class="reader-badge badge-disconnected">GETRENNT</span>';
                
                const lastRead = reader.last_read ?
                    new Date(reader.last_read).toLocaleTimeString('de-DE') :
                    'Keine';
                
                card.innerHTML = `
                    <div class="reader-header">
                        <span class="reader-name">${reader.id}</span>
                        ${badge}
                    </div>
                    <div class="reader-info">
                        <strong>Host:</strong> ${reader.host}:${reader.port}
                    </div>
                    <div class="reader-info">
                        <strong>Reads:</strong> ${reader.reads_count || 0}
                    </div>
                    <div class="reader-info">
                        <strong>Letzte Erfassung:</strong> ${lastRead}
                    </div>
                `;
                
                container.appendChild(card);
            });
        }
        
        function updateReadsCounts(data) {
            document.getElementById('buffer-count').textContent = data.buffered_count || 0;
            document.getElementById('total-reads').textContent = data.total_reads || 0;
            
            const bufferCard = document.querySelector('[id="buffer-count"]').parentElement.parentElement;
            if (data.buffered_count > 0) {
                bufferCard.style.borderColor = '#ff9500';
            } else {
                bufferCard.style.borderColor = '#00a86b';
            }
        }
        
        async function fetchReadsLog() {
            try {
                const response = await fetch(`${API_BASE}/reads/latest?limit=30`);
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                
                const reads = await response.json();
                const logsContainer = document.getElementById('reads-log');
                logsContainer.innerHTML = '';
                
                if (reads.length === 0) {
                    logsContainer.innerHTML = '<div class="empty-state">⏳ Keine Reads erfasst</div>';
                    return;
                }
                
                reads.reverse().forEach(read => {
                    const div = document.createElement('div');
                    div.className = 'read-entry';
                    const time = new Date(read.timestamp).toLocaleTimeString('de-DE');
                    
                    div.innerHTML = `
                        <span class="read-time">${time}</span>
                        <span class="read-reader">${read.reader_id}</span>
                        <span class="read-tag">${read.tag_id}</span>
                    `;
                    
                    logsContainer.appendChild(div);
                });
                
            } catch (error) {
                console.error('Fehler beim Abrufen der Reads:', error);
            }
        }
        
        function updateErrorState() {
            document.getElementById('system-status').textContent = '❌';
            document.getElementById('system-status').className = 'status-value status-error';
            document.getElementById('system-text').textContent = 'Verbindungsfehler';
            document.getElementById('readers-container').innerHTML =
                '<div class="empty-state">⚠️ Verbindung zur Middleware fehlgeschlagen</div>';
        }
        
        function updateLastUpdate() {
            const now = new Date();
            document.getElementById('last-update').textContent = now.toLocaleTimeString('de-DE');
        }
        
        // Initial load
        fetchStatus();
        fetchReadsLog();
        
        // Refresh every 2 seconds
        setInterval(() => {
            fetchStatus();
            fetchReadsLog();
        }, 2000);
    </script>
</body>
</html>

EOF


#############################
# App.main ==> Programmfile #
#############################

sudo cat > ~/raceresult-middleware/app/main.py << 'EOF'

## **Datei 2: app/main.py (Optimierte Middleware)**

# ```python
#!/usr/bin/env python3
"""
RaceResult RFID Middleware - Raspberry Pi 3 Native
Lightweight Flask-basierte Middleware ohne Docker
"""

from flask import Flask, jsonify, request, send_from_directory
from functools import wraps
import sqlite3
import json
import logging
import os
from datetime import datetime, timedelta
from pathlib import Path
import socket
import threading
import time
from dotenv import load_dotenv

# ==================== KONFIGURATION ====================

load_dotenv()

APP_DIR = Path(__file__).parent.parent
DB_PATH = APP_DIR / 'data' / 'timing_data.db'
CONFIG_PATH = APP_DIR / 'config' / 'config.json'
LOG_PATH = APP_DIR / 'logs'
WWW_PATH = APP_DIR / 'www'

# Verzeichnisse erstellen
DB_PATH.parent.mkdir(parents=True, exist_ok=True)
LOG_PATH.mkdir(parents=True, exist_ok=True)

# Logging
logging.basicConfig(
    level=os.getenv('LOG_LEVEL', 'INFO'),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_PATH / 'middleware.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Flask App
app = Flask(__name__)
app.config['JSON_SORT_KEYS'] = False

# ==================== DATENBANK ====================

class DatabaseManager:
    """Verwaltet SQLite Datenbank für RFID-Reads"""
    
    def __init__(self, db_path):
        self.db_path = db_path
        self.init_db()
    
    def init_db(self):
        """Initialisiere SQLite mit optimierten Settings"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Optimierung für Pi3
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA synchronous=NORMAL")
        cursor.execute("PRAGMA cache_size=-32000")
        cursor.execute("PRAGMA temp_store=MEMORY")
        
        # Tabelle erstellen
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS rfid_reads (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                reader_id TEXT NOT NULL,
                tag_id TEXT NOT NULL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                synced INTEGER DEFAULT 0,
                synced_at DATETIME
            )
        """)
        
        # Index für schnelle Abfragen
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_synced 
            ON rfid_reads(synced)
        """)
        
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_timestamp 
            ON rfid_reads(timestamp)
        """)
        
        conn.commit()
        conn.close()
        
        logger.info(f"📊 Datenbank initialisiert: {self.db_path}")
    
    def add_read(self, reader_id, tag_id):
        """Füge RFID-Read zur Datenbank hinzu"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute("""
                INSERT INTO rfid_reads (reader_id, tag_id)
                VALUES (?, ?)
            """, (reader_id, tag_id))
            
            conn.commit()
            conn.close()
            
            logger.debug(f"✓ Read: {reader_id} -> {tag_id}")
            return True
            
        except Exception as e:
            logger.error(f"✗ Fehler beim Speichern: {e}")
            return False
    
    def get_unsynced_reads(self, limit=100):
        """Hole nicht synchronisierte Reads"""
        try:
            conn = sqlite3.connect(self.db_path)
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT id, reader_id, tag_id, timestamp
                FROM rfid_reads
                WHERE synced = 0
                ORDER BY id ASC
                LIMIT ?
            """, (limit,))
            
            reads = [dict(row) for row in cursor.fetchall()]
            conn.close()
            return reads
            
        except Exception as e:
            logger.error(f"✗ Fehler beim Abrufen: {e}")
            return []
    
    def mark_synced(self, read_ids):
        """Markiere Reads als synchronisiert"""
        if not read_ids:
            return 0
        
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            placeholders = ','.join('?' * len(read_ids))
            cursor.execute(f"""
                UPDATE rfid_reads
                SET synced = 1, synced_at = CURRENT_TIMESTAMP
                WHERE id IN ({placeholders})
            """, read_ids)
            
            count = cursor.rowcount
            conn.commit()
            conn.close()
            
            logger.debug(f"✓ {count} Reads als synchronisiert markiert")
            return count
            
        except Exception as e:
            logger.error(f"✗ Fehler beim Markieren: {e}")
            return 0
    
    def get_latest_reads(self, limit=20):
        """Hole neueste Reads"""
        try:
            conn = sqlite3.connect(self.db_path)
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT reader_id, tag_id, timestamp
                FROM rfid_reads
                ORDER BY id DESC
                LIMIT ?
            """, (limit,))
            
            reads = [dict(row) for row in cursor.fetchall()]
            conn.close()
            return reads
            
        except Exception as e:
            logger.error(f"✗ Fehler: {e}")
            return []
    
    def get_stats(self):
        """Hole Statistiken"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute("SELECT COUNT(*) FROM rfid_reads")
            total = cursor.fetchone()[0]
            
            cursor.execute("SELECT COUNT(*) FROM rfid_reads WHERE synced = 0")
            unsynced = cursor.fetchone()[0]
            
            cursor.execute("SELECT COUNT(*) FROM rfid_reads WHERE DATE(timestamp) = DATE('now')")
            today = cursor.fetchone()[0]
            
            cursor.execute("""
                SELECT reader_id, COUNT(*) as count
                FROM rfid_reads
                GROUP BY reader_id
            """)
            by_reader = {row[0]: row[1] for row in cursor.fetchall()}
            
            conn.close()
            
            return {
                'total_reads': total,
                'unsynced_reads': unsynced,
                'reads_today': today,
                'by_reader': by_reader
            }
            
        except Exception as e:
            logger.error(f"✗ Fehler beim Abrufen von Stats: {e}")
            return {}

# ==================== READER LISTENER ====================

class ReaderListener:
    """Lauscht auf RFID-Daten von Readern"""
    
    def __init__(self, config_path, db_manager):
        self.config_path = config_path
        self.db = db_manager
        self.readers = {}
        self.running = False
        self.load_config()
    
    def load_config(self):
        """Lade Reader-Konfiguration"""
        try:
            with open(self.config_path) as f:
                config = json.load(f)
            
            self.readers = {r['id']: r for r in config.get('readers', [])}
            logger.info(f"📡 {len(self.readers)} Reader konfiguriert")
            
        except Exception as e:
            logger.error(f"✗ Fehler beim Laden der Config: {e}")
            self.readers = {}
    
    def start(self):
        """Starte Reader-Listener"""
        self.running = True
        
        for reader_id, reader_config in self.readers.items():
            thread = threading.Thread(
                target=self._listen_reader,
                args=(reader_id, reader_config),
                daemon=True
            )
            thread.start()
            logger.info(f"🔄 Listener für {reader_id} gestartet")
    
    def stop(self):
        """Stoppe Listener"""
        self.running = False
        logger.info("⛔ Listener gestoppt")
    
    def _listen_reader(self, reader_id, config):
        """Höre auf einen Reader"""
        host = config.get('host')
        port = config.get('port', 4001)
        
        while self.running:
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(10)
                sock.connect((host, port))
                
                logger.info(f"✓ {reader_id} verbunden ({host}:{port})")
                
                while self.running:
                    try:
                        data = sock.recv(1024).decode('utf-8').strip()
                        
                        if data:
                            self._process_read(reader_id, data)
                    
                    except socket.timeout:
                        continue
                    except Exception as e:
                        logger.warning(f"⚠️ {reader_id} Fehler: {e}")
                        break
                
                sock.close()
                
            except ConnectionRefusedError:
                logger.debug(f"⏳ {reader_id} nicht erreichbar, Retry in 5s...")
                time.sleep(5)
            
            except Exception as e:
                logger.warning(f"⚠️ {reader_id} Fehler: {e}")
                time.sleep(5)
    
    def _process_read(self, reader_id, data):
        """Verarbeite RFID-Read"""
        # Hier würde die Reader-spezifische Protokoll-Verarbeitung stattfinden
        # Beispiel: tag_id = data.strip()
        
        tag_id = data  # Vereinfacht
        
        if tag_id and len(tag_id) > 0:
            self.db.add_read(reader_id, tag_id)

# ==================== GLOBALE INSTANZEN ====================

db = DatabaseManager(DB_PATH)
listener = ReaderListener(CONFIG_PATH, db)

# ==================== API ENDPOINTS ====================

@app.route('/')
def index():
    """Serve Dashboard"""
    return send_from_directory(WWW_PATH, 'index.html')

@app.route('/api/status')
def get_status():
    """System-Status"""
    stats = db.get_stats()
    
    return jsonify({
        'timestamp': datetime.now().isoformat(),
        'system_healthy': True,
        'api_configured': True,
        'api_connected': True,
        'readers': [
            {
                'id': reader_id,
                'host': config.get('host'),
                'port': config.get('port', 4001),
                'connected': True,
                'reads_count': stats.get('by_reader', {}).get(reader_id, 0),
                'last_read': None
            }
            for reader_id, config in listener.readers.items()
        ],
        'buffered_count': stats.get('unsynced_reads', 0),
        'total_reads': stats.get('reads_today', 0)
    })

@app.route('/api/reads/latest')
def get_latest_reads():
    """Letzte RFID-Reads"""
    limit = request.args.get('limit', 20, type=int)
    reads = db.get_latest_reads(limit)
    return jsonify(reads)

@app.route('/api/reads/add', methods=['POST'])
def add_read():
    """Neuen Read hinzufügen (Test/Debug)"""
    data = request.get_json()
    
    reader_id = data.get('reader_id')
    tag_id = data.get('tag_id')
    
    if not reader_id or not tag_id:
        return jsonify({'error': 'reader_id und tag_id erforderlich'}), 400
    
    success = db.add_read(reader_id, tag_id)
    
    return jsonify({
        'status': 'ok' if success else 'error',
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/stats')
def get_stats():
    """Detaillierte Statistiken"""
    stats = db.get_stats()
    return jsonify(stats)

@app.route('/api/metrics')
def metrics():
    """Prometheus-kompatible Metriken"""
    stats = db.get_stats()
    
    metrics_text = f"""# HELP buffered_reads Anzahl gepufferter Reads
# TYPE buffered_reads gauge
buffered_reads {stats.get('unsynced_reads', 0)}

# HELP total_reads_today Gesamtzahl Reads heute
# TYPE total_reads_today counter
total_reads_today {stats.get('reads_today', 0)}

# HELP total_reads_all Gesamtzahl aller Reads
# TYPE total_reads_all counter
total_reads_all {stats.get('total_reads', 0)}
"""
    
    return metrics_text, 200, {'Content-Type': 'text/plain; charset=utf-8'}

@app.route('/api/sync', methods=['POST'])
def sync_api():
    """Synchronisiere mit RaceResult API (Placeholder)"""
    unsynced = db.get_unsynced_reads()
    
    if not unsynced:
        return jsonify({'synced': 0, 'status': 'ok'})
    
    # TODO: Hier würde die RaceResult API-Integration stattfinden
    # Für jetzt: Simuliere erfolgreiche Sync
    read_ids = [r['id'] for r in unsynced]
    synced = db.mark_synced(read_ids)
    
    return jsonify({
        'synced': synced,
        'timestamp': datetime.now().isoformat(),
        'status': 'ok'
    })

@app.errorhandler(404)
def not_found(e):
    return jsonify({'error': 'Not Found'}), 404

@app.errorhandler(500)
def server_error(e):
    logger.error(f"Server Error: {e}")
    return jsonify({'error': 'Internal Server Error'}), 500

# ==================== MAIN ====================

if __name__ == '__main__':
    try:
        logger.info("=" * 60)
        logger.info("🚀 RaceResult RFID Middleware - Native Installation")
        logger.info("=" * 60)
        logger.info(f"📂 Verzeichnis: {APP_DIR}")
        logger.info(f"💾 Datenbank: {DB_PATH}")
        logger.info(f"📡 Reader: {len(listener.readers)}")
        
        # Starte Reader-Listener
        listener.start()
        
        # Starte Flask
        logger.info("🌐 Starte Flask auf 0.0.0.0:5000")
        app.run(
            host='0.0.0.0',
            port=5000,
            debug=False,
            threaded=True,
            use_reloader=False
        )
    
    except KeyboardInterrupt:
        logger.info("⛔ Shutdown...")
        listener.stop()
    
    except Exception as e:
        logger.error(f"💥 Fehler: {e}", exc_info=True)

EOF
