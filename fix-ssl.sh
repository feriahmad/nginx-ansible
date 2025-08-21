#!/bin/bash

# SSL Fix Script
# This script fixes SSL certificate issues and ensures HTTPS works

set -e

echo "=== SSL Certificate Fix Script ==="
echo ""

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo privileges"
   echo "Usage: sudo ./fix-ssl.sh"
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

# Check current nginx status
echo "Checking nginx status..."
systemctl status nginx --no-pager -l

echo ""
echo "Checking nginx configuration..."
nginx -t

echo ""
echo "Checking current SSL certificates..."
if [[ -d "/etc/letsencrypt/live/amisgmbh.com" ]]; then
    echo "✓ Main domain certificate exists"
    certbot certificates | grep amisgmbh.com || true
else
    echo "✗ Main domain certificate missing"
fi

if [[ -d "/etc/letsencrypt/live/api.amisgmbh.com" ]]; then
    echo "✓ API domain certificate exists"
    certbot certificates | grep api.amisgmbh.com || true
else
    echo "✗ API domain certificate missing"
fi

echo ""
echo "Checking domain DNS resolution..."
echo "Main domain:"
nslookup amisgmbh.com || echo "DNS resolution failed for amisgmbh.com"
echo ""
echo "API domain:"
nslookup api.amisgmbh.com || echo "DNS resolution failed for api.amisgmbh.com"

echo ""
echo "Checking if domains point to this server..."
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "Unable to get server IP")
echo "Server IP: $SERVER_IP"

# Check if ports are open
echo ""
echo "Checking port accessibility..."
netstat -tuln | grep ":80 " && echo "✓ Port 80 is open" || echo "✗ Port 80 is not accessible"
netstat -tuln | grep ":443 " && echo "✓ Port 443 is open" || echo "✗ Port 443 is not accessible"

echo ""
echo "Checking UFW firewall status..."
ufw status

echo ""
echo "=== Attempting SSL Certificate Fix ==="

# Stop nginx temporarily
echo "Stopping nginx temporarily..."
systemctl stop nginx

# Try to obtain certificates using standalone mode first
echo "Attempting to obtain SSL certificates using standalone mode..."

# Remove any existing certificates to start fresh
echo "Cleaning up any existing certificates..."
certbot delete --cert-name amisgmbh.com --non-interactive || true
certbot delete --cert-name api.amisgmbh.com --non-interactive || true

# Obtain certificates for both domains
echo "Obtaining SSL certificate for both domains..."
certbot certonly --standalone \
    -d amisgmbh.com \
    -d api.amisgmbh.com \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    --expand || {
    echo "SSL certificate generation failed. Checking individual domains..."
    
    # Try individual domains
    echo "Trying main domain only..."
    certbot certonly --standalone \
        -d amisgmbh.com \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" || echo "Main domain certificate failed"
    
    echo "Trying API domain only..."
    certbot certonly --standalone \
        -d api.amisgmbh.com \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" || echo "API domain certificate failed"
}

# Start nginx
echo "Starting nginx..."
systemctl start nginx

# Now use certbot nginx mode to configure nginx automatically
echo "Configuring nginx with SSL using certbot..."
certbot --nginx \
    -d amisgmbh.com \
    -d api.amisgmbh.com \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    --redirect || {
    echo "Nginx SSL configuration failed. Trying individual domains..."
    
    certbot --nginx \
        -d amisgmbh.com \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --redirect || echo "Main domain nginx SSL failed"
    
    certbot --nginx \
        -d api.amisgmbh.com \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --redirect || echo "API domain nginx SSL failed"
}

# Test nginx configuration
echo ""
echo "Testing nginx configuration..."
nginx -t

# Reload nginx
echo "Reloading nginx..."
systemctl reload nginx

# Check final status
echo ""
echo "=== Final Status Check ==="
echo "SSL Certificates:"
certbot certificates

echo ""
echo "Nginx status:"
systemctl status nginx --no-pager -l

echo ""
echo "Testing HTTPS access..."
echo "Main domain HTTPS test:"
curl -I -k https://amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTPS test failed for main domain"

echo "API domain HTTPS test:"
curl -I -k https://api.amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTPS test failed for API domain"

echo ""
echo "=== SSL Fix Complete ==="
echo ""
echo "If HTTPS still doesn't work, check:"
echo "1. Domain DNS points to this server IP: $SERVER_IP"
echo "2. Firewall allows ports 80 and 443"
echo "3. Applications are running on localhost:6061 and localhost:6062"
echo ""
echo "Check nginx logs: sudo tail -f /var/log/nginx/error.log"
