# Nginx Ansible Playbook with SSL and Subdomain Configuration

This Ansible playbook automatically sets up nginx with SSL certificates and subdomain configuration for a web application with separate frontend and backend services.

## Overview

This setup configures:
- **Frontend Domain**: `amisgmbh.com` → `localhost:6062`
- **Backend API Domain**: `api.amisgmbh.com` → `localhost:6061`
- **SSL Certificates**: Automatic Let's Encrypt SSL certificates with auto-renewal
- **HTTPS Redirect**: Automatic HTTP to HTTPS redirection
- **Security Headers**: Modern security headers and SSL configuration
- **CORS Support**: Proper CORS configuration for API subdomain

## Prerequisites

1. **Domain Configuration**: Ensure both domains point to your server:
   - `amisgmbh.com` → Your server IP
   - `api.amisgmbh.com` → Your server IP

2. **Server Requirements**:
   - Ubuntu 20.04 LTS (optimized for this version)
   - Root or sudo access
   - Ports 80 and 443 open (automatically configured with UFW)
   - Internet connectivity for Let's Encrypt

3. **Applications Running**:
   - Frontend application on `localhost:6062`
   - Backend API on `localhost:6061`

## File Structure

```
nginx-ansible/
├── nginx-setup.yml           # Main Ansible playbook
├── inventory.ini             # Ansible inventory file
├── ansible.cfg              # Ansible configuration
├── run-playbook.sh          # Execution script
├── templates/
│   ├── nginx-main.conf.j2   # Frontend nginx configuration
│   └── nginx-api.conf.j2    # API nginx configuration
└── README.md               # This file
```

## Quick Start

### Option 1: Quick Setup (Recommended)
Uses default email configuration without prompts:
```bash
sudo ./quick-setup.sh
```

### Option 2: Interactive Setup
Allows you to customize email during setup:
```bash
sudo ./run-playbook.sh
```

### Option 3: Custom Email Configuration
1. **Edit the configuration file**:
   ```bash
   nano config.yml
   # Change: default_email: "admin@amisgmbh.com" to your email
   ```

2. **Run quick setup**:
   ```bash
   sudo ./quick-setup.sh
   ```

## Manual Execution

If you prefer to run the playbook manually:

```bash
# Install Ansible (if not already installed) - Ubuntu 20.04
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible

# Run with default email
ansible-playbook nginx-setup.yml -i inventory.ini

# Run with custom email
ansible-playbook nginx-setup.yml -i inventory.ini --extra-vars "email_address=your-email@example.com"
```

## Configuration

### Email Configuration
The setup uses a default email (`admin@amisgmbh.com`) for Let's Encrypt certificates. You can:

1. **Use default email**: Just run `sudo ./quick-setup.sh`
2. **Change default email**: Edit `config.yml` file
3. **Use custom email**: Run `sudo ./run-playbook.sh` and enter email when prompted
4. **Set environment variable**: `EMAIL=your@email.com sudo ./quick-setup.sh`

## Configuration Details

### Frontend Configuration (`amisgmbh.com`)
- Proxies all requests to `localhost:6062`
- Handles static files with caching
- WebSocket support for real-time features
- Security headers for protection

### API Configuration (`api.amisgmbh.com`)
- Proxies all requests to `localhost:6061`
- CORS headers configured for frontend domain
- Rate limiting for API protection
- Health check endpoint support
- Optimized for API responses

### SSL Configuration
- Let's Encrypt certificates with automatic renewal
- Modern TLS protocols (TLSv1.2, TLSv1.3)
- Strong cipher suites
- HSTS headers for security

## Customization

### Changing Ports
Edit the variables in `nginx-setup.yml`:
```yaml
vars:
  fe_port: 6062  # Change frontend port
  be_port: 6061  # Change backend port
```

### Changing Domains
Edit the variables in `nginx-setup.yml`:
```yaml
vars:
  domain: "yourdomain.com"
  api_domain: "api.yourdomain.com"
```

### Adding Rate Limiting
The API configuration includes rate limiting. To enable it, add this to your main nginx configuration:
```nginx
http {
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    # ... rest of configuration
}
```

## Troubleshooting

### SSL Certificate Issues
1. **Domain not pointing to server**:
   ```bash
   # Check DNS resolution
   nslookup amisgmbh.com
   nslookup api.amisgmbh.com
   ```

2. **Firewall blocking ports** (automatically handled by playbook):
   ```bash
   # Check UFW status
   sudo ufw status
   
   # Manually allow ports if needed
   sudo ufw allow 80
   sudo ufw allow 443
   ```

3. **Manual certificate generation**:
   ```bash
   sudo certbot --nginx -d amisgmbh.com -d api.amisgmbh.com
   ```

### Nginx Issues
1. **Check nginx status**:
   ```bash
   sudo systemctl status nginx
   ```

2. **Test nginx configuration**:
   ```bash
   sudo nginx -t
   ```

3. **View nginx logs**:
   ```bash
   sudo tail -f /var/log/nginx/error.log
   sudo tail -f /var/log/nginx/amisgmbh.com_error.log
   sudo tail -f /var/log/nginx/api.amisgmbh.com_error.log
   ```

### Application Issues
1. **Check if applications are running**:
   ```bash
   # Check frontend
   curl http://localhost:6062
   
   # Check backend
   curl http://localhost:6061
   ```

2. **Start your applications** if they're not running

## Security Features

- **HTTPS Enforcement**: All HTTP traffic redirected to HTTPS
- **Security Headers**: HSTS, X-Frame-Options, X-Content-Type-Options, etc.
- **Modern SSL**: TLS 1.2+ with strong ciphers
- **Rate Limiting**: API endpoint protection
- **CORS Configuration**: Proper cross-origin resource sharing

## Maintenance

### Certificate Renewal
Certificates automatically renew via cron job. To manually renew:
```bash
sudo certbot renew
```

### Updating Configuration
1. Modify the template files in `templates/`
2. Re-run the playbook:
   ```bash
   ansible-playbook nginx-setup.yml -i inventory.ini
   ```

### Monitoring
- Check certificate expiry: `sudo certbot certificates`
- Monitor nginx access logs: `sudo tail -f /var/log/nginx/*_access.log`
- Monitor nginx error logs: `sudo tail -f /var/log/nginx/*_error.log`

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review nginx error logs
3. Verify domain DNS configuration
4. Ensure applications are running on correct ports

## License

This playbook is provided as-is for educational and production use.
