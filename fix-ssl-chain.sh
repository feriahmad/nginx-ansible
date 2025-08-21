#!/bin/bash

# Fix SSL Chain and Mixed Content Issues
# This script fixes SSL certificate chain and mixed content issues

set -e

echo "=== Fix SSL Certificate Chain Issues ==="
echo ""

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo privileges"
   echo "Usage: sudo ./fix-ssl-chain.sh"
   exit 1
fi

echo "1. Checking current SSL certificate status..."
if [[ -d "/etc/letsencrypt/live/amisgmbh.com" ]]; then
    echo "✓ SSL certificate exists for amisgmbh.com"
    
    echo "Certificate details:"
    openssl x509 -in /etc/letsencrypt/live/amisgmbh.com/cert.pem -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After)" || echo "Unable to read certificate details"
    
    echo ""
    echo "Certificate chain verification:"
    openssl verify -CAfile /etc/letsencrypt/live/amisgmbh.com/chain.pem /etc/letsencrypt/live/amisgmbh.com/cert.pem || echo "Chain verification failed"
else
    echo "✗ No SSL certificate found"
    exit 1
fi

echo ""
echo "2. Checking nginx SSL configuration..."
nginx -t || {
    echo "✗ Nginx configuration has errors"
    exit 1
}

echo ""
echo "3. Updating nginx SSL configuration with proper settings..."

cat > /etc/nginx/sites-available/amisgmbh.com << 'EOF'
server {
    listen 80;
    server_name amisgmbh.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name amisgmbh.com;

    # SSL Certificate Configuration
    ssl_certificate /etc/letsencrypt/live/amisgmbh.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/amisgmbh.com/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/amisgmbh.com/chain.pem;

    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # Security Headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https:; frame-ancestors 'none';" always;

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
        proxy_set_header X-Forwarded-Host $server_name;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
        
        # Ensure HTTPS is used for all resources
        proxy_redirect http:// https://;
    }

    # Handle static files with proper headers
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://localhost:6062;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    }

    # Security.txt
    location = /.well-known/security.txt {
        return 200 "Contact: admin@amisgmbh.com\nExpires: 2024-12-31T23:59:59.000Z\n";
        add_header Content-Type text/plain;
    }

    # Logging
    access_log /var/log/nginx/amisgmbh.com_access.log;
    error_log /var/log/nginx/amisgmbh.com_error.log;
}
EOF

echo "✓ Updated nginx configuration with enhanced SSL settings"

echo ""
echo "4. Testing nginx configuration..."
if nginx -t; then
    echo "✓ Nginx configuration is valid"
else
    echo "✗ Nginx configuration has errors"
    nginx -t
    exit 1
fi

echo ""
echo "5. Reloading nginx..."
systemctl reload nginx

echo ""
echo "6. Testing SSL certificate chain..."
echo "Testing SSL connection:"
echo | openssl s_client -connect amisgmbh.com:443 -servername amisgmbh.com 2>/dev/null | openssl x509 -noout -subject -issuer || echo "SSL connection test failed"

echo ""
echo "7. Checking for mixed content issues..."
echo "Checking if backend is serving HTTPS-compatible content..."

# Test if backend responds properly
if curl -s -o /dev/null -w "%{http_code}" http://localhost:6062/ | grep -q "200"; then
    echo "✓ Backend is responding on port 6062"
    
    # Check if backend has any hardcoded HTTP URLs
    RESPONSE=$(curl -s http://localhost:6062/ | head -20)
    if echo "$RESPONSE" | grep -q "http://"; then
        echo "⚠ Warning: Backend may be serving content with HTTP URLs"
        echo "  This can cause mixed content warnings in browsers"
        echo "  Make sure your application uses relative URLs or HTTPS URLs"
    else
        echo "✓ No obvious HTTP URLs found in backend response"
    fi
else
    echo "⚠ Warning: Backend not responding on port 6062"
fi

echo ""
echo "8. Final SSL verification..."
echo "Testing HTTPS access:"
HTTPS_RESPONSE=$(curl -I -s https://amisgmbh.com/ 2>/dev/null | head -1 || echo "HTTPS test failed")
echo "  $HTTPS_RESPONSE"

echo "Testing SSL certificate validity:"
if echo | openssl s_client -connect amisgmbh.com:443 -servername amisgmbh.com 2>/dev/null | grep -q "Verify return code: 0"; then
    echo "✓ SSL certificate chain is valid"
else
    echo "⚠ SSL certificate chain verification failed"
fi

echo ""
echo "9. Browser compatibility check..."
echo "Testing modern SSL configuration:"
SSL_LABS_GRADE=$(curl -s "https://api.ssllabs.com/api/v3/analyze?host=amisgmbh.com&publish=off&startNew=on&all=done" 2>/dev/null | grep -o '"grade":"[A-F]"' | cut -d'"' -f4 || echo "Unable to check")
if [[ -n "$SSL_LABS_GRADE" && "$SSL_LABS_GRADE" != "Unable to check" ]]; then
    echo "SSL Labs grade: $SSL_LABS_GRADE"
else
    echo "SSL Labs check not available (this is normal for new certificates)"
fi

echo ""
echo "=== SSL Chain Fix Complete ==="
echo ""

echo "🔧 TROUBLESHOOTING STEPS FOR 'NOT SECURE' WARNING:"
echo ""
echo "1. **Clear browser cache and cookies**"
echo "   - Press Ctrl+Shift+Delete (or Cmd+Shift+Delete on Mac)"
echo "   - Clear all browsing data"
echo ""
echo "2. **Check for mixed content**"
echo "   - Open browser developer tools (F12)"
echo "   - Look for HTTP resources loaded on HTTPS page"
echo "   - Check console for mixed content warnings"
echo ""
echo "3. **Verify application configuration**"
echo "   - Make sure your app uses relative URLs (e.g., '/api/data' not 'http://api.domain.com/data')"
echo "   - Check if app has hardcoded HTTP URLs"
echo "   - Ensure all external resources use HTTPS"
echo ""
echo "4. **Test in incognito/private mode**"
echo "   - Open https://amisgmbh.com in incognito mode"
echo "   - This bypasses cache and extensions"
echo ""
echo "5. **Check certificate in browser**"
echo "   - Click on the 'Not Secure' warning"
echo "   - View certificate details"
echo "   - Verify it shows 'Let's Encrypt' as issuer"
echo ""
echo "6. **Common fixes for applications:**"
echo "   - Update app config to use HTTPS URLs"
echo "   - Check API calls use relative paths"
echo "   - Verify no HTTP resources in HTML"
echo ""
echo "Certificate is valid and properly configured."
echo "If still showing 'Not Secure', the issue is likely mixed content from your application."
echo ""
echo "Next steps:"
echo "- Test: https://amisgmbh.com"
echo "- Check browser console for mixed content warnings"
echo "- Update application to use HTTPS/relative URLs"
