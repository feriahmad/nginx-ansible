#!/bin/bash

# Test script for nginx-ansible setup
# This script validates the configuration before running the main playbook

echo "=== Nginx Ansible Setup Validation ==="
echo ""

# Check if running on Ubuntu 20.04
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "$VERSION_ID" == "20.04" ]]; then
        echo "✓ Running on Ubuntu 20.04 LTS"
    else
        echo "⚠ Warning: This setup is optimized for Ubuntu 20.04, you're running $PRETTY_NAME"
    fi
else
    echo "⚠ Warning: Cannot detect OS version"
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "✓ Running with root privileges"
else
    echo "✗ Error: This script must be run with sudo privileges"
    echo "Usage: sudo ./test-setup.sh"
    exit 1
fi

# Check internet connectivity
echo ""
echo "Testing internet connectivity..."
if ping -c 1 google.com &> /dev/null; then
    echo "✓ Internet connectivity available"
else
    echo "✗ Error: No internet connectivity (required for Let's Encrypt)"
    exit 1
fi

# Check if ports 6061 and 6062 are available
echo ""
echo "Checking if application ports are available..."

if netstat -tuln 2>/dev/null | grep -q ":6061 "; then
    echo "✓ Port 6061 is in use (backend should be running here)"
else
    echo "⚠ Warning: Port 6061 is not in use - make sure your backend API is running on localhost:6061"
fi

if netstat -tuln 2>/dev/null | grep -q ":6062 "; then
    echo "✓ Port 6062 is in use (frontend should be running here)"
else
    echo "⚠ Warning: Port 6062 is not in use - make sure your frontend is running on localhost:6062"
fi

# Check DNS resolution for domains
echo ""
echo "Testing DNS resolution..."

if nslookup amisgmbh.com &> /dev/null; then
    echo "✓ amisgmbh.com resolves"
    SERVER_IP=$(curl -s ifconfig.me)
    DOMAIN_IP=$(nslookup amisgmbh.com | grep -A1 "Name:" | tail -1 | awk '{print $2}')
    if [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then
        echo "✓ amisgmbh.com points to this server ($SERVER_IP)"
    else
        echo "⚠ Warning: amisgmbh.com points to $DOMAIN_IP, but this server is $SERVER_IP"
    fi
else
    echo "✗ Error: amisgmbh.com does not resolve"
fi

if nslookup api.amisgmbh.com &> /dev/null; then
    echo "✓ api.amisgmbh.com resolves"
    API_DOMAIN_IP=$(nslookup api.amisgmbh.com | grep -A1 "Name:" | tail -1 | awk '{print $2}')
    if [[ "$SERVER_IP" == "$API_DOMAIN_IP" ]]; then
        echo "✓ api.amisgmbh.com points to this server ($SERVER_IP)"
    else
        echo "⚠ Warning: api.amisgmbh.com points to $API_DOMAIN_IP, but this server is $SERVER_IP"
    fi
else
    echo "✗ Error: api.amisgmbh.com does not resolve"
fi

# Check if required files exist
echo ""
echo "Checking required files..."

required_files=(
    "nginx-setup.yml"
    "inventory.ini"
    "ansible.cfg"
    "run-playbook.sh"
    "templates/nginx-main.conf.j2"
    "templates/nginx-api.conf.j2"
)

for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "✓ $file exists"
    else
        echo "✗ Error: $file is missing"
        exit 1
    fi
done

# Test ansible syntax
echo ""
echo "Testing Ansible playbook syntax..."
if command -v ansible-playbook &> /dev/null; then
    if ansible-playbook nginx-setup.yml --syntax-check &> /dev/null; then
        echo "✓ Ansible playbook syntax is valid"
    else
        echo "✗ Error: Ansible playbook syntax error"
        ansible-playbook nginx-setup.yml --syntax-check
        exit 1
    fi
else
    echo "⚠ Ansible not installed - will be installed during setup"
fi

echo ""
echo "=== Validation Complete ==="
echo ""
echo "Summary:"
echo "- Setup files are ready"
echo "- Make sure your applications are running on localhost:6061 (backend) and localhost:6062 (frontend)"
echo "- Ensure domains point to this server for SSL certificate generation"
echo ""
echo "Ready to run: sudo ./run-playbook.sh"
