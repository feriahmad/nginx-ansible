#!/bin/bash

# Quick Nginx Setup Script with SSL (No Prompts)
# This script runs the Ansible playbook using default configuration

set -e

echo "=== Quick Nginx Setup (Using Default Configuration) ==="
echo ""

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo privileges"
   echo "Usage: sudo ./quick-setup.sh"
   exit 1
fi

# Check if ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    echo "Ansible is not installed. Installing ansible for Ubuntu 20.04..."
    
    # Update package cache
    apt update
    
    # Install software-properties-common for add-apt-repository
    apt install -y software-properties-common
    
    # Add Ansible PPA for latest version
    add-apt-repository --yes --update ppa:ansible/ansible
    
    # Install Ansible
    apt install -y ansible
    
    echo "Ansible installed successfully!"
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

# Use default email without prompting
EMAIL="$DEFAULT_EMAIL"
echo "Using default email: $EMAIL"
echo ""

# Show configuration
echo "Configuration:"
echo "  - Frontend: amisgmbh.com -> localhost:6062"
echo "  - Backend API: api.amisgmbh.com -> localhost:6061"
echo "  - SSL Email: $EMAIL"
echo ""

# Run the playbook immediately
echo "Running Ansible playbook with default configuration..."
ansible-playbook nginx-setup.yml -i inventory.ini --extra-vars "email_address=$EMAIL"

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Your nginx configuration is now active with the following setup:"
echo "  - Frontend (amisgmbh.com) -> localhost:6062"
echo "  - Backend API (api.amisgmbh.com) -> localhost:6061"
echo "  - SSL certificates automatically managed by Let's Encrypt"
echo "  - Automatic HTTP to HTTPS redirect"
echo "  - CORS properly configured for API access"
echo ""
echo "Make sure your applications are running on:"
echo "  - Frontend: localhost:6062"
echo "  - Backend: localhost:6061"
echo ""
echo "SSL certificates will auto-renew via cron job."
echo ""
echo "To change default email, edit config.yml file."
