#!/bin/bash

# Reset to HTTP Script
# This script resets nginx configuration to HTTP-only to fix SSL loading issues

set -e

echo "=== Reset Nginx to HTTP Configuration ==="
echo ""

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo privileges"
   echo "Usage: sudo ./reset-to-http.sh"
   exit 1
fi

echo "1. Stopping nginx..."
systemctl stop nginx || echo "Nginx was already stopped"

echo ""
echo "2. Backing up current configurations..."
mkdir -p /tmp/nginx-backup-$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/tmp/nginx-backup-$(date +%Y%m%d-%H%M%S)"

if [[ -f "/etc/nginx/sites-enabled/amisgmbh.com" ]]; then
    cp /etc/nginx/sites-enabled/amisgmbh.com $BACKUP_DIR/
    echo "✓ Backed up main domain config"
fi

if [[ -f "/etc/nginx/sites-enabled/api.amisgmbh.com" ]]; then
    cp /etc/nginx/sites-enabled/api.amisgmbh.com $BACKUP_DIR/
    echo "✓ Backed up API domain config"
fi

echo "Backup saved to: $BACKUP_DIR"

echo ""
echo "3. Removing current configurations..."
rm -f /etc/nginx/sites-enabled/amisgmbh.com
rm -f /etc/nginx/sites-enabled/api.amisgmbh.com
rm -f /etc/nginx/sites-available/amisgmbh.com
rm -f /etc/nginx/sites-available/api.amisgmbh.com

echo ""
echo "4. Creating HTTP-only configurations..."

# Create main domain HTTP config
cat > /etc/nginx/sites-available/amisgmbh.com << 'EOF'
server {
    listen 80;
    server_name amisgmbh.com;

    # Security Headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Proxy settings for frontend application
    location / {
        proxy_pass http://localhost:6062;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
    }

    # Optional: Handle static files directly (if needed)
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://localhost:6062;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Logging
    access_log /var/log/nginx/amisgmbh.com_access.log;
    error_log /var/log/nginx/amisgmbh.com_error.log;
}
EOF

# Create API domain HTTP config
cat > /etc/nginx/sites-available/api.amisgmbh.com << 'EOF'
server {
    listen 80;
    server_name api.amisgmbh.com;

    # Security Headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # CORS configuration for API access
    location / {
        # Set allowed origins
        set $cors_origin "";
        if ($http_origin = "http://amisgmbh.com") {
            set $cors_origin "http://amisgmbh.com";
        }
        if ($http_origin = "https://amisgmbh.com") {
            set $cors_origin "https://amisgmbh.com";
        }
        if ($http_origin = "http://localhost:6062") {
            set $cors_origin "http://localhost:6062";
        }
        if ($http_origin = "https://localhost:6062") {
            set $cors_origin "https://localhost:6062";
        }
        # Allow any subdomain of the main domain
        if ($http_origin ~ "^https?://.*\.amisgmbh\.com$") {
            set $cors_origin $http_origin;
        }

        # Handle CORS preflight requests
        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin $cors_origin;
            add_header Access-Control-Allow-Methods 'GET, POST, PUT, DELETE, OPTIONS, PATCH';
            add_header Access-Control-Allow-Headers 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,Accept,Origin,X-Forwarded-For';
            add_header Access-Control-Max-Age 1728000;
            add_header Content-Type 'text/plain; charset=utf-8';
            add_header Content-Length 0;
            return 204;
        }

        # Add CORS headers for all requests
        add_header Access-Control-Allow-Origin $cors_origin always;
        add_header Access-Control-Allow-Methods 'GET, POST, PUT, DELETE, OPTIONS, PATCH' always;
        add_header Access-Control-Allow-Headers 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,Accept,Origin,X-Forwarded-For' always;
        add_header Access-Control-Expose-Headers 'Content-Length,Content-Range' always;

        # Proxy settings for backend API
        proxy_pass http://localhost:6061;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
        
        # Buffer settings for API responses
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }

    # API health check endpoint (optional)
    location /health {
        proxy_pass http://localhost:6061/health;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        access_log off;
    }

    # Logging
    access_log /var/log/nginx/api.amisgmbh.com_access.log;
    error_log /var/log/nginx/api.amisgmbh.com_error.log;
}
EOF

echo ""
echo "5. Enabling configurations..."
ln -sf /etc/nginx/sites-available/amisgmbh.com /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/api.amisgmbh.com /etc/nginx/sites-enabled/

echo ""
echo "6. Testing nginx configuration..."
if nginx -t; then
    echo "✓ Nginx configuration is valid"
else
    echo "✗ Nginx configuration has errors"
    exit 1
fi

echo ""
echo "7. Starting nginx..."
systemctl start nginx
systemctl enable nginx

echo ""
echo "8. Checking nginx status..."
if systemctl is-active --quiet nginx; then
    echo "✓ Nginx is running successfully"
else
    echo "✗ Nginx failed to start"
    systemctl status nginx
    exit 1
fi

echo ""
echo "9. Testing HTTP access..."
echo "Main domain HTTP test:"
HTTP_MAIN=$(curl -I -s http://amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTP test failed")
echo "  $HTTP_MAIN"

echo "API domain HTTP test:"
HTTP_API=$(curl -I -s http://api.amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTP test failed")
echo "  $HTTP_API"

echo ""
echo "=== Reset Complete ==="
echo ""
echo "✓ Nginx is now running with HTTP-only configuration"
echo "✓ CORS is properly configured for API access"
echo "✓ Both domains should be accessible via HTTP"
echo ""
echo "Next steps:"
echo "1. Test HTTP access: http://amisgmbh.com and http://api.amisgmbh.com"
echo "2. If HTTP works, run SSL setup: sudo ./setup-ssl-proper.sh"
echo ""
echo "Backup of old configs saved to: $BACKUP_DIR"
