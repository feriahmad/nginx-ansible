#!/bin/bash

# Nginx Setup Script with SSL
# This script runs the Ansible playbook to setup nginx with SSL

set -e

echo "=== Nginx Setup with SSL and Subdomain Configuration ==="
echo ""

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo privileges"
   echo "Usage: sudo ./run-playbook.sh"
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

# Prompt for email if not provided
if [[ -z "$EMAIL" ]]; then
    read -p "Enter your email for Let's Encrypt certificates: " EMAIL
    export EMAIL
fi

# Check if domains are accessible (optional warning)
echo "WARNING: Make sure the following domains point to this server:"
echo "  - amisgmbh.com"
echo "  - api.amisgmbh.com"
echo ""
echo "If domains are not properly configured, SSL certificate generation will fail."
echo ""

read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Run the playbook
echo "Running Ansible playbook..."
ansible-playbook nginx-setup.yml -i inventory.ini --extra-vars "email=$EMAIL"

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Your nginx configuration is now active with the following setup:"
echo "  - Frontend (amisgmbh.com) -> localhost:6062"
echo "  - Backend API (api.amisgmbh.com) -> localhost:6061"
echo "  - SSL certificates automatically managed by Let's Encrypt"
echo "  - Automatic HTTP to HTTPS redirect"
echo ""
echo "Make sure your applications are running on:"
echo "  - Frontend: localhost:6062"
echo "  - Backend: localhost:6061"
echo ""
echo "SSL certificates will auto-renew via cron job."
