#!/bin/bash

# Proper SSL Setup Script
# This script sets up SSL certificates properly after HTTP is working

set -e

echo "=== Proper SSL Setup Script ==="
echo ""

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo privileges"
   echo "Usage: sudo ./setup-ssl-proper.sh"
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

# Check if HTTP works
if curl -s -o /dev/null -w "%{http_code}" http://amisgmbh.com/ | grep -q "200\|301\|302"; then
    echo "✓ Main domain HTTP is working"
else
    echo "✗ Main domain HTTP is not working. Please fix HTTP first"
    exit 1
fi

if curl -s -o /dev/null -w "%{http_code}" http://api.amisgmbh.com/ | grep -q "200\|301\|302"; then
    echo "✓ API domain HTTP is working"
else
    echo "✗ API domain HTTP is not working. Please fix HTTP first"
    exit 1
fi

echo ""
echo "2. Checking DNS resolution..."
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "Unable to get server IP")
echo "Server IP: $SERVER_IP"

MAIN_IP=$(nslookup amisgmbh.com | grep -A1 "Name:" | tail -1 | awk '{print $2}' 2>/dev/null || echo "Unable to resolve")
API_IP=$(nslookup api.amisgmbh.com | grep -A1 "Name:" | tail -1 | awk '{print $2}' 2>/dev/null || echo "Unable to resolve")

if [[ "$MAIN_IP" != "$SERVER_IP" ]]; then
    echo "⚠ Warning: amisgmbh.com points to $MAIN_IP but server is $SERVER_IP"
    echo "SSL certificate generation may fail if DNS is not correct"
fi

if [[ "$API_IP" != "$SERVER_IP" ]]; then
    echo "⚠ Warning: api.amisgmbh.com points to $API_IP but server is $SERVER_IP"
    echo "SSL certificate generation may fail if DNS is not correct"
fi

echo ""
read -p "Do you want to continue with SSL setup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "3. Cleaning up any existing certificates..."
certbot delete --cert-name amisgmbh.com --non-interactive 2>/dev/null || echo "No existing main domain certificate"
certbot delete --cert-name api.amisgmbh.com --non-interactive 2>/dev/null || echo "No existing API domain certificate"

echo ""
echo "4. Stopping nginx temporarily for standalone certificate generation..."
systemctl stop nginx

echo ""
echo "5. Generating SSL certificates using standalone mode..."

# Try to get certificate for both domains together
echo "Attempting to get certificate for both domains..."
if certbot certonly --standalone \
    -d amisgmbh.com \
    -d api.amisgmbh.com \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    --expand; then
    echo "✓ Successfully obtained certificate for both domains"
    CERT_SUCCESS=true
else
    echo "Failed to get certificate for both domains. Trying individual domains..."
    CERT_SUCCESS=false
    
    # Try main domain
    echo "Trying main domain (amisgmbh.com)..."
    if certbot certonly --standalone \
        -d amisgmbh.com \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL"; then
        echo "✓ Successfully obtained certificate for main domain"
        MAIN_CERT=true
    else
        echo "✗ Failed to obtain certificate for main domain"
        MAIN_CERT=false
    fi
    
    # Try API domain
    echo "Trying API domain (api.amisgmbh.com)..."
    if certbot certonly --standalone \
        -d api.amisgmbh.com \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL"; then
        echo "✓ Successfully obtained certificate for API domain"
        API_CERT=true
    else
        echo "✗ Failed to obtain certificate for API domain"
        API_CERT=false
    fi
fi

echo ""
echo "6. Starting nginx..."
systemctl start nginx

echo ""
echo "7. Checking which certificates were created..."
if [[ -d "/etc/letsencrypt/live/amisgmbh.com" ]]; then
    echo "✓ Main domain certificate exists"
    MAIN_CERT_EXISTS=true
else
    echo "✗ Main domain certificate missing"
    MAIN_CERT_EXISTS=false
fi

if [[ -d "/etc/letsencrypt/live/api.amisgmbh.com" ]]; then
    echo "✓ API domain certificate exists"
    API_CERT_EXISTS=true
else
    echo "✗ API domain certificate missing"
    API_CERT_EXISTS=false
fi

echo ""
echo "8. Updating nginx configurations with SSL..."

# Update main domain config if certificate exists
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

# Update API domain config if certificate exists
if [[ "$API_CERT_EXISTS" == "true" ]]; then
    echo "Updating API domain configuration with SSL..."
    cat > /etc/nginx/sites-available/api.amisgmbh.com << 'EOF'
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

    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
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
    echo "✓ Updated API domain configuration with SSL"
else
    echo "⚠ Keeping API domain as HTTP-only (no certificate)"
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
else
    echo "Testing HTTP for main domain (no SSL certificate):"
    HTTP_MAIN=$(curl -I -s http://amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTP test failed")
    echo "  $HTTP_MAIN"
fi

if [[ "$API_CERT_EXISTS" == "true" ]]; then
    echo "Testing HTTPS for API domain:"
    HTTPS_API=$(curl -I -k -s https://api.amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTPS test failed")
    echo "  $HTTPS_API"
else
    echo "Testing HTTP for API domain (no SSL certificate):"
    HTTP_API=$(curl -I -s http://api.amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTP test failed")
    echo "  $HTTP_API"
fi

echo ""
echo "=== SSL Setup Complete ==="
echo ""

if [[ "$MAIN_CERT_EXISTS" == "true" && "$API_CERT_EXISTS" == "true" ]]; then
    echo "🎉 SUCCESS: Both domains now have SSL certificates!"
    echo "✓ Main domain: https://amisgmbh.com"
    echo "✓ API domain: https://api.amisgmbh.com"
    echo "✓ Automatic HTTP to HTTPS redirect enabled"
    echo "✓ CORS properly configured for API access"
    echo "✓ Automatic certificate renewal configured"
elif [[ "$MAIN_CERT_EXISTS" == "true" || "$API_CERT_EXISTS" == "true" ]]; then
    echo "⚠ PARTIAL SUCCESS: Some domains have SSL certificates"
    [[ "$MAIN_CERT_EXISTS" == "true" ]] && echo "✓ Main domain: https://amisgmbh.com"
    [[ "$API_CERT_EXISTS" == "true" ]] && echo "✓ API domain: https://api.amisgmbh.com"
    echo ""
    echo "Domains without SSL certificates will continue to work via HTTP"
    echo "You can retry SSL setup later when DNS is properly configured"
else
    echo "⚠ SSL certificate generation failed for both domains"
    echo "Both domains will continue to work via HTTP"
    echo ""
    echo "Common reasons for SSL failure:"
    echo "1. DNS not pointing to this server"
    echo "2. Firewall blocking port 80/443"
    echo "3. Domain not accessible from internet"
    echo ""
    echo "You can retry SSL setup later: sudo ./setup-ssl-proper.sh"
fi

echo ""
echo "Certificate status:"
certbot certificates 2>/dev/null || echo "No certificates found"
