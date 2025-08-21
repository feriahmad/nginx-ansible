# Panduan Mengatasi Masalah HTTPS

## Masalah yang Dialami
- HTTP berfungsi normal
- HTTPS tidak bisa diakses (ERR_CONNECTION_REFUSED)
- Script `quick-setup.sh` dan `run-playbook.sh` tidak mengaktifkan HTTPS

## Langkah-langkah Perbaikan

### 1. Cek Status Saat Ini
```bash
sudo ./check-ssl.sh
```
Script ini akan memberikan laporan lengkap tentang:
- Status nginx
- Keberadaan SSL certificate
- Konfigurasi DNS
- Status aplikasi
- Akses HTTP/HTTPS

### 2. Perbaiki SSL Certificate
```bash
sudo ./fix-ssl.sh
```
Script ini akan:
- Menghentikan nginx sementara
- Menghapus certificate lama yang bermasalah
- Membuat certificate baru menggunakan Let's Encrypt
- Mengkonfigurasi nginx untuk HTTPS
- Restart nginx

### 3. Verifikasi Manual

#### Cek Certificate
```bash
sudo certbot certificates
```

#### Cek Nginx Configuration
```bash
sudo nginx -t
sudo systemctl status nginx
```

#### Test HTTPS
```bash
curl -I -k https://amisgmbh.com/
curl -I -k https://api.amisgmbh.com/
```

### 4. Troubleshooting Umum

#### A. Domain Tidak Mengarah ke Server
**Masalah**: DNS tidak mengarah ke server Anda
**Solusi**:
```bash
# Cek IP server
curl ifconfig.me

# Cek DNS domain
nslookup amisgmbh.com
nslookup api.amisgmbh.com

# Update DNS record di provider domain Anda
# A record: amisgmbh.com -> IP_SERVER_ANDA
# A record: api.amisgmbh.com -> IP_SERVER_ANDA
```

#### B. Firewall Memblokir Port 443
**Masalah**: Port 443 tidak terbuka
**Solusi**:
```bash
sudo ufw allow 443
sudo ufw status
```

#### C. Certificate Generation Gagal
**Masalah**: Let's Encrypt tidak bisa membuat certificate
**Solusi**:
```bash
# Coba manual dengan standalone mode
sudo systemctl stop nginx
sudo certbot certonly --standalone -d amisgmbh.com -d api.amisgmbh.com
sudo systemctl start nginx
```

#### D. Nginx Configuration Error
**Masalah**: Nginx config bermasalah setelah SSL setup
**Solusi**:
```bash
# Backup dan reset config
sudo cp /etc/nginx/sites-enabled/amisgmbh.com /etc/nginx/sites-enabled/amisgmbh.com.backup
sudo cp /etc/nginx/sites-enabled/api.amisgmbh.com /etc/nginx/sites-enabled/api.amisgmbh.com.backup

# Re-run setup
sudo ./quick-setup.sh
```

### 5. Langkah Manual Jika Script Gagal

#### Step 1: Install Certificate Manual
```bash
sudo systemctl stop nginx
sudo certbot certonly --standalone \
    -d amisgmbh.com \
    -d api.amisgmbh.com \
    --email admin@amisgmbh.com \
    --agree-tos \
    --non-interactive
```

#### Step 2: Update Nginx Config Manual
Edit `/etc/nginx/sites-enabled/amisgmbh.com`:
```nginx
server {
    listen 80;
    server_name amisgmbh.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name amisgmbh.com;

    ssl_certificate /etc/letsencrypt/live/amisgmbh.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/amisgmbh.com/privkey.pem;

    location / {
        proxy_pass http://localhost:6062;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Edit `/etc/nginx/sites-enabled/api.amisgmbh.com`:
```nginx
server {
    listen 80;
    server_name api.amisgmbh.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.amisgmbh.com;

    ssl_certificate /etc/letsencrypt/live/api.amisgmbh.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.amisgmbh.com/privkey.pem;

    # CORS Headers
    add_header Access-Control-Allow-Origin '*' always;
    add_header Access-Control-Allow-Methods 'GET, POST, PUT, DELETE, OPTIONS, PATCH' always;
    add_header Access-Control-Allow-Headers 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,Accept,Origin,X-Forwarded-For' always;

    location / {
        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin '*';
            add_header Access-Control-Allow-Methods 'GET, POST, PUT, DELETE, OPTIONS, PATCH';
            add_header Access-Control-Allow-Headers 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,Accept,Origin,X-Forwarded-For';
            add_header Access-Control-Max-Age 1728000;
            add_header Content-Type 'text/plain; charset=utf-8';
            add_header Content-Length 0;
            return 204;
        }

        proxy_pass http://localhost:6061;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

#### Step 3: Test dan Restart
```bash
sudo nginx -t
sudo systemctl start nginx
sudo systemctl reload nginx
```

### 6. Verifikasi Final

#### Test HTTPS Access
```bash
# Test main domain
curl -I https://amisgmbh.com/

# Test API domain
curl -I https://api.amisgmbh.com/

# Test CORS
curl -H "Origin: https://amisgmbh.com" \
     -H "Access-Control-Request-Method: GET" \
     -X OPTIONS https://api.amisgmbh.com/
```

#### Browser Test
- Buka https://amisgmbh.com di browser
- Pastikan tidak ada error SSL
- Test API call dari frontend

### 7. Monitoring dan Maintenance

#### Auto-renewal Certificate
```bash
# Cek auto-renewal
sudo crontab -l | grep certbot

# Test renewal
sudo certbot renew --dry-run
```

#### Monitor Logs
```bash
# Nginx error logs
sudo tail -f /var/log/nginx/error.log

# Domain-specific logs
sudo tail -f /var/log/nginx/amisgmbh.com_error.log
sudo tail -f /var/log/nginx/api.amisgmbh.com_error.log
```

## Script yang Tersedia

1. **`sudo ./check-ssl.sh`** - Cek status SSL dan troubleshooting
2. **`sudo ./fix-ssl.sh`** - Perbaiki masalah SSL secara otomatis
3. **`sudo ./quick-setup.sh`** - Setup ulang dengan konfigurasi default
4. **`sudo ./run-playbook.sh`** - Setup interaktif dengan opsi custom

## Catatan Penting

1. **Pastikan aplikasi berjalan** di localhost:6061 (backend) dan localhost:6062 (frontend)
2. **DNS harus mengarah** ke IP server Anda
3. **Port 80 dan 443** harus terbuka di firewall
4. **Let's Encrypt membutuhkan** akses internet untuk verifikasi domain

Jika masih ada masalah, jalankan `sudo ./check-ssl.sh` untuk diagnosis lengkap.
