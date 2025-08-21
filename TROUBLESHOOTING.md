# Troubleshooting Guide - SSL Certificate Issue Fix

## Issues Fixed

### 1. SSL Certificate Loading Error
The original playbook was failing with the error:
```
nginx: [emerg] cannot load certificate "/etc/letsencrypt/live/amisgmbh.com/fullchain.pem": BIO_new_file() failed
```

This happened because the nginx configuration templates were trying to load SSL certificates that didn't exist yet.

### 2. CORS Error for API Access
The frontend was unable to access the API due to CORS (Cross-Origin Resource Sharing) restrictions, showing errors like:
```
Access to fetch at 'api.amisgmbh.com' from origin 'amisgmbh.com' has been blocked by CORS policy
```

This happened because the API nginx configuration wasn't properly configured to allow cross-origin requests from the frontend domain.

## Solution Applied

### 1. Updated Nginx Templates
- **Before**: Templates included both HTTP and HTTPS server blocks with SSL certificate paths
- **After**: Templates now only include HTTP server blocks initially
- **Why**: Let's Encrypt's `certbot --nginx` automatically modifies nginx configuration to add SSL

### 2. Modified SSL Certificate Process
- **Before**: Pre-configured SSL paths in templates, then tried to obtain certificates
- **After**: Start with HTTP-only configuration, then let certbot modify nginx config automatically
- **Benefits**: 
  - No SSL certificate loading errors
  - Certbot handles SSL configuration automatically
  - Automatic HTTP to HTTPS redirect setup

### 3. Enhanced Error Handling
- Added `ignore_errors: yes` for SSL certificate tasks
- Added debug output to show SSL setup results
- Graceful handling when domains don't point to server yet

### 4. CORS Configuration Fix
- **Before**: Limited CORS headers that didn't handle all scenarios
- **After**: Comprehensive CORS configuration that allows:
  - Both HTTP and HTTPS access from the main domain
  - Access from localhost during development
  - Subdomain access
  - All necessary HTTP methods (GET, POST, PUT, DELETE, OPTIONS, PATCH)
  - Proper preflight request handling

## Current Workflow

1. **Install nginx and dependencies**
2. **Create HTTP-only configurations** for both domains
3. **Start nginx** with HTTP configurations
4. **Obtain SSL certificates** using certbot --nginx
5. **Certbot automatically modifies** nginx configs to add SSL
6. **Setup automatic renewal** via cron

## Usage Instructions

### Quick Start
```bash
sudo ./run-playbook.sh
```

### Manual Execution
```bash
ansible-playbook nginx-setup.yml -i inventory.ini --extra-vars "email=your-email@example.com"
```

### If SSL Setup Fails
If the SSL certificate generation fails (domains not pointing to server), you can:

1. **Fix DNS configuration** to point domains to your server
2. **Run SSL setup manually**:
   ```bash
   sudo certbot --nginx -d amisgmbh.com -d api.amisgmbh.com
   ```

## Validation

### Before Running Playbook
```bash
sudo ./test-setup.sh
```

### After Running Playbook
1. **Check nginx status**:
   ```bash
   sudo systemctl status nginx
   ```

2. **Test HTTP access**:
   ```bash
   curl -H "Host: amisgmbh.com" http://localhost
   curl -H "Host: api.amisgmbh.com" http://localhost
   ```

3. **Test HTTPS access** (if SSL was successful):
   ```bash
   curl -H "Host: amisgmbh.com" https://localhost
   curl -H "Host: api.amisgmbh.com" https://localhost
   ```

4. **Check SSL certificates**:
   ```bash
   sudo certbot certificates
   ```

## Configuration Files

### HTTP-Only Templates
- `templates/nginx-main.conf.j2`: Frontend HTTP configuration
- `templates/nginx-api.conf.j2`: API HTTP configuration

### After SSL Setup
Certbot automatically modifies these files to add:
- SSL certificate paths
- HTTPS server blocks
- HTTP to HTTPS redirects
- SSL security settings

### CORS Configuration
The API template includes comprehensive CORS settings that allow:
- Access from `http://amisgmbh.com` and `https://amisgmbh.com`
- Access from `http://localhost:6062` and `https://localhost:6062` (development)
- Access from any subdomain of `amisgmbh.com`
- All standard HTTP methods
- Proper handling of preflight OPTIONS requests

## Common Issues and Solutions

### 1. Domain Not Resolving
**Problem**: DNS not pointing to server
**Solution**: 
```bash
# Check DNS
nslookup amisgmbh.com
nslookup api.amisgmbh.com

# Update DNS records to point to your server IP
```

### 2. Firewall Blocking
**Problem**: Ports 80/443 blocked
**Solution**: 
```bash
# Check UFW status
sudo ufw status

# Allow ports (done automatically by playbook)
sudo ufw allow 80
sudo ufw allow 443
```

### 3. Applications Not Running
**Problem**: Backend/frontend not accessible
**Solution**:
```bash
# Check if applications are running
curl http://localhost:6061  # Backend
curl http://localhost:6062  # Frontend

# Start your applications if needed
```

### 4. CORS Issues
**Problem**: Frontend can't access API due to CORS errors
**Solution**:
```bash
# Test CORS headers
curl -H "Origin: https://amisgmbh.com" -H "Access-Control-Request-Method: GET" -H "Access-Control-Request-Headers: Content-Type" -X OPTIONS http://api.amisgmbh.com/

# Check nginx configuration
sudo nginx -t
sudo systemctl reload nginx

# Check nginx logs for CORS-related errors
sudo tail -f /var/log/nginx/api.amisgmbh.com_error.log
```

### 4. SSL Certificate Renewal
**Problem**: Certificates expiring
**Solution**:
```bash
# Manual renewal
sudo certbot renew

# Check auto-renewal (set up by playbook)
sudo crontab -l | grep certbot
```

## Security Features

### HTTP Configuration
- Security headers (X-Frame-Options, X-Content-Type-Options, etc.)
- CORS configuration for API
- Proper proxy headers

### HTTPS Configuration (Added by Certbot)
- Modern TLS protocols (1.2, 1.3)
- Strong cipher suites
- HSTS headers
- Automatic HTTP to HTTPS redirect

## Next Steps

1. **Ensure applications are running** on localhost:6061 and localhost:6062
2. **Configure DNS** to point domains to your server
3. **Run the playbook** using `sudo ./run-playbook.sh`
4. **Test the setup** using the validation commands above
5. **Monitor logs** in `/var/log/nginx/` for any issues

The playbook now handles the SSL certificate setup process correctly and should work without the previous SSL loading errors.
