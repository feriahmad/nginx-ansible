#!/bin/bash

# SSL Status Check Script
# This script checks the current SSL configuration and provides troubleshooting info

echo "=== SSL Status Check ==="
echo ""

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo privileges"
   echo "Usage: sudo ./check-ssl.sh"
   exit 1
fi

echo "1. Checking nginx status..."
if systemctl is-active --quiet nginx; then
    echo "✓ Nginx is running"
else
    echo "✗ Nginx is not running"
    echo "  Fix: sudo systemctl start nginx"
fi

echo ""
echo "2. Checking nginx configuration..."
if nginx -t &>/dev/null; then
    echo "✓ Nginx configuration is valid"
else
    echo "✗ Nginx configuration has errors:"
    nginx -t
fi

echo ""
echo "3. Checking SSL certificates..."
if [[ -d "/etc/letsencrypt/live/amisgmbh.com" ]]; then
    echo "✓ Main domain certificate exists"
    echo "  Certificate details:"
    certbot certificates | grep -A 10 amisgmbh.com || echo "  Unable to get certificate details"
else
    echo "✗ Main domain certificate missing"
fi

if [[ -d "/etc/letsencrypt/live/api.amisgmbh.com" ]]; then
    echo "✓ API domain certificate exists"
    echo "  Certificate details:"
    certbot certificates | grep -A 10 api.amisgmbh.com || echo "  Unable to get certificate details"
else
    echo "✗ API domain certificate missing"
fi

echo ""
echo "4. Checking domain DNS resolution..."
echo "Main domain (amisgmbh.com):"
if nslookup amisgmbh.com &>/dev/null; then
    MAIN_IP=$(nslookup amisgmbh.com | grep -A1 "Name:" | tail -1 | awk '{print $2}' 2>/dev/null || echo "Unable to parse IP")
    echo "  ✓ Resolves to: $MAIN_IP"
else
    echo "  ✗ DNS resolution failed"
fi

echo "API domain (api.amisgmbh.com):"
if nslookup api.amisgmbh.com &>/dev/null; then
    API_IP=$(nslookup api.amisgmbh.com | grep -A1 "Name:" | tail -1 | awk '{print $2}' 2>/dev/null || echo "Unable to parse IP")
    echo "  ✓ Resolves to: $API_IP"
else
    echo "  ✗ DNS resolution failed"
fi

echo ""
echo "5. Checking server IP..."
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "Unable to get server IP")
echo "Server public IP: $SERVER_IP"

if [[ "$MAIN_IP" == "$SERVER_IP" ]]; then
    echo "✓ Main domain points to this server"
else
    echo "✗ Main domain does NOT point to this server"
    echo "  Domain IP: $MAIN_IP, Server IP: $SERVER_IP"
fi

if [[ "$API_IP" == "$SERVER_IP" ]]; then
    echo "✓ API domain points to this server"
else
    echo "✗ API domain does NOT point to this server"
    echo "  Domain IP: $API_IP, Server IP: $SERVER_IP"
fi

echo ""
echo "6. Checking firewall (UFW)..."
ufw status | head -10

echo ""
echo "7. Checking port accessibility..."
if netstat -tuln | grep -q ":80 "; then
    echo "✓ Port 80 (HTTP) is open"
else
    echo "✗ Port 80 (HTTP) is not accessible"
fi

if netstat -tuln | grep -q ":443 "; then
    echo "✓ Port 443 (HTTPS) is open"
else
    echo "✗ Port 443 (HTTPS) is not accessible"
fi

echo ""
echo "8. Checking applications..."
if curl -s http://localhost:6062 &>/dev/null; then
    echo "✓ Frontend application is running on port 6062"
else
    echo "✗ Frontend application is NOT running on port 6062"
fi

if curl -s http://localhost:6061 &>/dev/null; then
    echo "✓ Backend application is running on port 6061"
else
    echo "✗ Backend application is NOT running on port 6061"
fi

echo ""
echo "9. Testing HTTP access..."
echo "Main domain HTTP:"
HTTP_MAIN=$(curl -I -s http://amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTP test failed")
echo "  $HTTP_MAIN"

echo "API domain HTTP:"
HTTP_API=$(curl -I -s http://api.amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTP test failed")
echo "  $HTTP_API"

echo ""
echo "10. Testing HTTPS access..."
echo "Main domain HTTPS:"
HTTPS_MAIN=$(curl -I -k -s https://amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTPS test failed")
echo "  $HTTPS_MAIN"

echo "API domain HTTPS:"
HTTPS_API=$(curl -I -k -s https://api.amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTPS test failed")
echo "  $HTTPS_API"

echo ""
echo "11. Checking nginx configuration files..."
echo "Main domain config:"
if [[ -f "/etc/nginx/sites-enabled/amisgmbh.com" ]]; then
    echo "  ✓ /etc/nginx/sites-enabled/amisgmbh.com exists"
else
    echo "  ✗ /etc/nginx/sites-enabled/amisgmbh.com missing"
fi

echo "API domain config:"
if [[ -f "/etc/nginx/sites-enabled/api.amisgmbh.com" ]]; then
    echo "  ✓ /etc/nginx/sites-enabled/api.amisgmbh.com exists"
else
    echo "  ✗ /etc/nginx/sites-enabled/api.amisgmbh.com missing"
fi

echo ""
echo "12. Recent nginx error logs:"
echo "Last 5 error log entries:"
tail -5 /var/log/nginx/error.log 2>/dev/null || echo "No error logs found"

echo ""
echo "=== TROUBLESHOOTING RECOMMENDATIONS ==="
echo ""

# Provide specific recommendations based on findings
if [[ ! -d "/etc/letsencrypt/live/amisgmbh.com" ]] || [[ ! -d "/etc/letsencrypt/live/api.amisgmbh.com" ]]; then
    echo "🔧 SSL CERTIFICATE ISSUE:"
    echo "   Run: sudo ./fix-ssl.sh"
    echo ""
fi

if [[ "$MAIN_IP" != "$SERVER_IP" ]] || [[ "$API_IP" != "$SERVER_IP" ]]; then
    echo "🔧 DNS CONFIGURATION ISSUE:"
    echo "   Update your DNS records to point to: $SERVER_IP"
    echo "   - amisgmbh.com A record -> $SERVER_IP"
    echo "   - api.amisgmbh.com A record -> $SERVER_IP"
    echo ""
fi

if ! systemctl is-active --quiet nginx; then
    echo "🔧 NGINX NOT RUNNING:"
    echo "   sudo systemctl start nginx"
    echo "   sudo systemctl enable nginx"
    echo ""
fi

if ! curl -s http://localhost:6061 &>/dev/null || ! curl -s http://localhost:6062 &>/dev/null; then
    echo "🔧 APPLICATION NOT RUNNING:"
    echo "   Make sure your applications are running on:"
    echo "   - Frontend: localhost:6062"
    echo "   - Backend: localhost:6061"
    echo ""
fi

echo "🔧 QUICK FIXES:"
echo "   1. Fix SSL: sudo ./fix-ssl.sh"
echo "   2. Restart nginx: sudo systemctl restart nginx"
echo "   3. Check logs: sudo tail -f /var/log/nginx/error.log"
echo "   4. Re-run setup: sudo ./quick-setup.sh"
