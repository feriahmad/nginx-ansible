#!/bin/bash

# SSL Setup for Main Domain Only
# This script sets up SSL certificate only for the main domain (amisgmbh.com)

set -e

echo "=== SSL Setup for Main Domain Only ==="
echo ""

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo privileges"
   echo "Usage: sudo ./setup-ssl-main-only.sh"
   exit 1
fi

# Read default email from config file
if [[ -f "config.yml" ]]; then
    DEFAULT_EMAIL=$(grep "default_email:" config.yml | cut -d'"' -f2)
    if [[ -z "$DEFAULT_EMAIL" ]]; then
        DEFAULT_EMAIL="admin@amisgmbh.com"
    fi
else
    DEFAULT_EMAIL="admin@amisgmbh.com"
fi

EMAIL="$DEFAULT_EMAIL"
echo "Using email: $EMAIL"
echo ""

echo "1. Checking prerequisites..."

# Check if nginx is running
if ! systemctl is-active --quiet nginx; then
    echo "✗ Nginx is not running. Please run 'sudo ./reset-to-http.sh' first"
    exit 1
fi
echo "✓ Nginx is running"

# Check if main domain HTTP works
if curl -s -o /dev/null -w "%{http_code}" http://amisgmbh.com/ | grep -q "200\|301\|302"; then
    echo "✓ Main domain HTTP is working"
else
    echo "✗ Main domain HTTP is not working. Please fix HTTP first"
    exit 1
fi

echo "ℹ Skipping API domain as requested"

echo ""
echo "2. Checking DNS resolution for main domain..."
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "Unable to get server IP")
echo "Server IP: $SERVER_IP"

MAIN_IP=$(nslookup amisgmbh.com | grep -A1 "Name:" | tail -1 | awk '{print $2}' 2>/dev/null || echo "Unable to resolve")

if [[ "$MAIN_IP" != "$SERVER_IP" ]]; then
    echo "⚠ Warning: amisgmbh.com points to $MAIN_IP but server is $SERVER_IP"
    echo "SSL certificate generation may fail if DNS is not correct"
    echo ""
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
else
    echo "✓ amisgmbh.com points to this server ($SERVER_IP)"
fi

echo ""
echo "3. Cleaning up any existing certificates for main domain..."
certbot delete --cert-name amisgmbh.com --non-interactive 2>/dev/null || echo "No existing main domain certificate"

echo ""
echo "4. Stopping nginx temporarily for standalone certificate generation..."
systemctl stop nginx

echo ""
echo "5. Generating SSL certificate for main domain only..."

if certbot certonly --standalone \
    -d amisgmbh.com \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL"; then
    echo "✓ Successfully obtained certificate for main domain"
    MAIN_CERT_SUCCESS=true
else
    echo "✗ Failed to obtain certificate for main domain"
    MAIN_CERT_SUCCESS=false
fi

echo ""
echo "6. Starting nginx..."
systemctl start nginx

echo ""
echo "7. Checking certificate creation..."
if [[ -d "/etc/letsencrypt/live/amisgmbh.com" ]]; then
    echo "✓ Main domain certificate exists"
    MAIN_CERT_EXISTS=true
else
    echo "✗ Main domain certificate missing"
    MAIN_CERT_EXISTS=false
fi

echo ""
echo "8. Updating nginx configuration for main domain..."

if [[ "$MAIN_CERT_EXISTS" == "true" ]]; then
    echo "Updating main domain configuration with SSL..."
    cat > /etc/nginx/sites-available/amisgmbh.com << 'EOF'
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

    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # SSL session tickets
    ssl_session_tickets off;

    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
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
    echo "✓ Updated main domain configuration with SSL"
else
    echo "⚠ Keeping main domain as HTTP-only (no certificate)"
fi

echo ""
echo "9. Testing nginx configuration..."
if nginx -t; then
    echo "✓ Nginx configuration is valid"
else
    echo "✗ Nginx configuration has errors"
    nginx -t
    exit 1
fi

echo ""
echo "10. Reloading nginx..."
systemctl reload nginx

echo ""
echo "11. Setting up automatic certificate renewal..."
if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    echo "✓ Added automatic certificate renewal to crontab"
else
    echo "✓ Automatic certificate renewal already configured"
fi

echo ""
echo "12. Final testing..."

if [[ "$MAIN_CERT_EXISTS" == "true" ]]; then
    echo "Testing HTTPS for main domain:"
    HTTPS_MAIN=$(curl -I -k -s https://amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTPS test failed")
    echo "  $HTTPS_MAIN"
    
    echo "Testing HTTP redirect:"
    HTTP_REDIRECT=$(curl -I -s http://amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTP redirect test failed")
    echo "  $HTTP_REDIRECT"
else
    echo "Testing HTTP for main domain (no SSL certificate):"
    HTTP_MAIN=$(curl -I -s http://amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTP test failed")
    echo "  $HTTP_MAIN"
fi

echo ""
echo "=== SSL Setup Complete for Main Domain ==="
echo ""

if [[ "$MAIN_CERT_EXISTS" == "true" ]]; then
    echo "🎉 SUCCESS: Main domain now has SSL certificate!"
    echo "✓ Main domain: https://amisgmbh.com"
    echo "✓ Automatic HTTP to HTTPS redirect enabled"
    echo "✓ Automatic certificate renewal configured"
    echo ""
    echo "API domain (api.amisgmbh.com) remains as HTTP-only as requested"
    echo "You can setup SSL for API domain later if needed"
else
    echo "⚠ SSL certificate generation failed for main domain"
    echo "Main domain will continue to work via HTTP"
    echo ""
    echo "Common reasons for SSL failure:"
    echo "1. DNS not pointing to this server"
    echo "2. Firewall blocking port 80/443"
    echo "3. Domain not accessible from internet"
    echo ""
    echo "You can retry SSL setup later: sudo ./setup-ssl-main-only.sh"
fi

echo ""
echo "Certificate status:"
certbot certificates 2>/dev/null || echo "No certificates found"

echo ""
echo "Next steps:"
echo "- Test main domain: https://amisgmbh.com"
echo "- API domain remains: http://api.amisgmbh.com"
echo "- Setup API SSL later if needed: sudo ./setup-ssl-proper.sh"
