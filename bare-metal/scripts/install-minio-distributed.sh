#!/bin/bash

# MinIO Distributed Mode Installation Script for Bare Metal
# Version: 1.0
# Description: Automated installation and optimization of MinIO in distributed mode
# Requirements: 4+ nodes with NVMe SSDs, Ubuntu/CentOS/RHEL

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
MINIO_VERSION="RELEASE.2024-01-16T16-07-38Z"
MINIO_USER="minio"
MINIO_GROUP="minio"
MINIO_HOME="/opt/minio"
MINIO_DATA_DIR="/mnt/minio"
MINIO_CONFIG_DIR="/etc/minio"
MINIO_LOG_DIR="/var/log/minio"
MINIO_PORT="9000"
MINIO_CONSOLE_PORT="9001"

# Default cluster configuration (can be overridden)
CLUSTER_NODES=(
    "minio-node1.example.com"
    "minio-node2.example.com"
    "minio-node3.example.com"
    "minio-node4.example.com"
)

DRIVES_PER_NODE=4

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_action() {
    echo -e "${CYAN}[ACTION]${NC} $1"
}

# Usage information
usage() {
    echo "MinIO Distributed Mode Installation Script"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --nodes         Comma-separated list of node hostnames/IPs"
    echo "  --drives        Number of drives per node (default: 4)"
    echo "  --data-dir      Base data directory (default: /mnt/minio)"
    echo "  --user          MinIO service user (default: minio)"
    echo "  --port          MinIO API port (default: 9000)"
    echo "  --console-port  MinIO Console port (default: 9001)"
    echo "  --optimize      Apply system optimizations (default: true)"
    echo "  --help          Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --nodes node1,node2,node3,node4 --drives 8"
    echo "  $0 --optimize --data-dir /data/minio"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --nodes)
            IFS=',' read -ra CLUSTER_NODES <<< "$2"
            shift 2
            ;;
        --drives)
            DRIVES_PER_NODE="$2"
            shift 2
            ;;
        --data-dir)
            MINIO_DATA_DIR="$2"
            shift 2
            ;;
        --user)
            MINIO_USER="$2"
            shift 2
            ;;
        --port)
            MINIO_PORT="$2"
            shift 2
            ;;
        --console-port)
            MINIO_CONSOLE_PORT="$2"
            shift 2
            ;;
        --optimize)
            APPLY_OPTIMIZATIONS=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        OS_VERSION=$(cat /etc/redhat-release | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    else
        log_error "Unsupported operating system"
        exit 1
    fi
    
    case $OS in
        ubuntu|debian)
            OS_FAMILY="debian"
            PACKAGE_MANAGER="apt"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            OS_FAMILY="redhat"
            PACKAGE_MANAGER="yum"
            ;;
        *)
            log_warning "Unknown OS: $OS. Assuming RedHat family."
            OS_FAMILY="redhat"
            PACKAGE_MANAGER="yum"
            ;;
    esac
    
    log_info "Detected OS: $OS $OS_VERSION ($OS_FAMILY family)"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check minimum number of nodes
    if [ ${#CLUSTER_NODES[@]} -lt 4 ]; then
        log_error "MinIO distributed mode requires at least 4 nodes"
        exit 1
    fi
    
    # Check if nodes are reachable
    for node in "${CLUSTER_NODES[@]}"; do
        if ! ping -c 1 "$node" &> /dev/null; then
            log_warning "Node $node is not reachable"
        else
            log_success "Node $node is reachable"
        fi
    done
    
    # Check available disk space
    REQUIRED_SPACE=$((DRIVES_PER_NODE * 100)) # 100GB per drive minimum
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        log_warning "Available space ($AVAILABLE_SPACE GB) may be insufficient (required: $REQUIRED_SPACE GB)"
    fi
}

# Install dependencies
install_dependencies() {
    log_action "Installing dependencies..."
    
    case $OS_FAMILY in
        debian)
            apt update
            apt install -y curl wget gnupg2 software-properties-common
            ;;
        redhat)
            if command -v dnf &> /dev/null; then
                dnf install -y curl wget gnupg2
            else
                yum install -y curl wget gnupg2
            fi
            ;;
    esac
    
    log_success "Dependencies installed"
}

# Create MinIO user and directories
create_user_and_directories() {
    log_action "Creating MinIO user and directories..."
    
    # Create MinIO user
    if ! id "$MINIO_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$MINIO_HOME" "$MINIO_USER"
        log_success "Created MinIO user: $MINIO_USER"
    else
        log_info "MinIO user already exists: $MINIO_USER"
    fi
    
    # Create directories
    mkdir -p "$MINIO_HOME" "$MINIO_CONFIG_DIR" "$MINIO_LOG_DIR"
    
    # Create data directories
    for i in $(seq 1 $DRIVES_PER_NODE); do
        mkdir -p "${MINIO_DATA_DIR}/disk${i}"
        chown -R "$MINIO_USER:$MINIO_GROUP" "${MINIO_DATA_DIR}/disk${i}"
    done
    
    # Set permissions
    chown -R "$MINIO_USER:$MINIO_GROUP" "$MINIO_HOME" "$MINIO_CONFIG_DIR" "$MINIO_LOG_DIR"
    chmod 755 "$MINIO_HOME" "$MINIO_CONFIG_DIR"
    chmod 750 "$MINIO_LOG_DIR"
    
    log_success "User and directories created"
}

# Download and install MinIO
install_minio() {
    log_action "Downloading and installing MinIO..."
    
    # Download MinIO binary
    MINIO_URL="https://dl.min.io/server/minio/release/linux-amd64/archive/minio.${MINIO_VERSION}"
    
    if ! curl -fsSL "$MINIO_URL" -o "$MINIO_HOME/minio"; then
        log_error "Failed to download MinIO binary"
        exit 1
    fi
    
    # Make executable
    chmod +x "$MINIO_HOME/minio"
    chown "$MINIO_USER:$MINIO_GROUP" "$MINIO_HOME/minio"
    
    # Create symlink
    ln -sf "$MINIO_HOME/minio" /usr/local/bin/minio
    
    # Download MinIO Client (mc)
    MC_URL="https://dl.min.io/client/mc/release/linux-amd64/mc"
    curl -fsSL "$MC_URL" -o "$MINIO_HOME/mc"
    chmod +x "$MINIO_HOME/mc"
    ln -sf "$MINIO_HOME/mc" /usr/local/bin/mc
    
    log_success "MinIO installed successfully"
}

# Generate MinIO configuration
generate_config() {
    log_action "Generating MinIO configuration..."
    
    # Generate random credentials if not provided
    if [ -z "$MINIO_ROOT_USER" ]; then
        MINIO_ROOT_USER="minioadmin"
    fi
    
    if [ -z "$MINIO_ROOT_PASSWORD" ]; then
        MINIO_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    fi
    
    # Create environment file
    cat > "$MINIO_CONFIG_DIR/minio.env" << EOF
# MinIO Configuration
MINIO_ROOT_USER=$MINIO_ROOT_USER
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD

# Performance Optimization
MINIO_CACHE_DRIVES="/tmp/cache1,/tmp/cache2"
MINIO_CACHE_EXCLUDE="*.tmp"
MINIO_CACHE_QUOTA=80
MINIO_CACHE_AFTER=3
MINIO_CACHE_WATERMARK_LOW=70
MINIO_CACHE_WATERMARK_HIGH=90

# Compression
MINIO_COMPRESS=on
MINIO_COMPRESS_EXTENSIONS=".txt,.log,.csv,.json,.tar,.xml,.bin"
MINIO_COMPRESS_MIME_TYPES="text/*,application/json,application/xml"

# API Optimization
MINIO_API_REQUESTS_MAX=10000
MINIO_API_REQUESTS_DEADLINE=10s
MINIO_API_READY_DEADLINE=10s

# Logging
MINIO_LOG_LEVEL=INFO
MINIO_LOG_FILE=$MINIO_LOG_DIR/minio.log

# Console
MINIO_BROWSER_REDIRECT_URL=http://$(hostname -I | awk '{print $1}'):$MINIO_CONSOLE_PORT
EOF
    
    # Set permissions
    chown "$MINIO_USER:$MINIO_GROUP" "$MINIO_CONFIG_DIR/minio.env"
    chmod 600 "$MINIO_CONFIG_DIR/minio.env"
    
    log_success "Configuration generated"
    log_info "Root User: $MINIO_ROOT_USER"
    log_info "Root Password: $MINIO_ROOT_PASSWORD"
}

# Create systemd service
create_systemd_service() {
    log_action "Creating systemd service..."
    
    # Build server command with all nodes and drives
    SERVER_CMD="minio server"
    for node in "${CLUSTER_NODES[@]}"; do
        for i in $(seq 1 $DRIVES_PER_NODE); do
            SERVER_CMD="$SERVER_CMD http://$node:$MINIO_PORT${MINIO_DATA_DIR}/disk$i"
        done
    done
    SERVER_CMD="$SERVER_CMD --console-address :$MINIO_CONSOLE_PORT"
    
    # Create systemd service file
    cat > /etc/systemd/system/minio.service << EOF
[Unit]
Description=MinIO Distributed Object Storage Server
Documentation=https://docs.min.io
Wants=network-online.target
After=network-online.target
AssertFileIsExecutable=$MINIO_HOME/minio

[Service]
WorkingDirectory=$MINIO_HOME
User=$MINIO_USER
Group=$MINIO_GROUP
EnvironmentFile=$MINIO_CONFIG_DIR/minio.env
ExecStart=$SERVER_CMD
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=minio

# Security settings
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=$MINIO_DATA_DIR $MINIO_LOG_DIR /tmp
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes

# Resource limits
LimitNOFILE=1048576
LimitNPROC=1048576
LimitMEMLOCK=infinity
LimitCORE=infinity

# Performance settings
IOSchedulingClass=1
IOSchedulingPriority=4
CPUSchedulingPolicy=2
CPUSchedulingPriority=50

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable minio
    
    log_success "Systemd service created and enabled"
}

# Apply system optimizations
apply_optimizations() {
    if [ "$APPLY_OPTIMIZATIONS" != "true" ]; then
        return 0
    fi
    
    log_action "Applying system optimizations..."
    
    # Run kernel optimization script if available
    if [ -f "../../../minio_kernel_optimize.sh" ]; then
        log_info "Running kernel optimization script..."
        bash ../../../minio_kernel_optimize.sh --force
    else
        log_warning "Kernel optimization script not found, applying basic optimizations..."
        
        # Basic kernel parameters
        cat >> /etc/sysctl.conf << EOF

# MinIO Performance Optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
vm.dirty_ratio = 5
vm.swappiness = 1
fs.file-max = 1048576
net.ipv4.tcp_congestion_control = bbr
EOF
        
        sysctl -p
    fi
    
    # Create cache directories
    mkdir -p /tmp/cache1 /tmp/cache2
    chown "$MINIO_USER:$MINIO_GROUP" /tmp/cache1 /tmp/cache2
    
    # Mount cache directories as tmpfs for performance
    if ! grep -q "/tmp/cache1" /etc/fstab; then
        echo "tmpfs /tmp/cache1 tmpfs defaults,size=4G,uid=$(id -u $MINIO_USER),gid=$(id -g $MINIO_GROUP) 0 0" >> /etc/fstab
        echo "tmpfs /tmp/cache2 tmpfs defaults,size=4G,uid=$(id -u $MINIO_USER),gid=$(id -g $MINIO_GROUP) 0 0" >> /etc/fstab
        mount -a
    fi
    
    log_success "System optimizations applied"
}

# Configure firewall
configure_firewall() {
    log_action "Configuring firewall..."
    
    # Check if firewall is active
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="$MINIO_PORT/tcp"
        firewall-cmd --permanent --add-port="$MINIO_CONSOLE_PORT/tcp"
        firewall-cmd --reload
        log_success "Firewalld configured"
    elif systemctl is-active --quiet ufw; then
        ufw allow "$MINIO_PORT/tcp"
        ufw allow "$MINIO_CONSOLE_PORT/tcp"
        log_success "UFW configured"
    else
        log_info "No active firewall detected"
    fi
}

# Start MinIO service
start_minio() {
    log_action "Starting MinIO service..."
    
    # Start and check status
    systemctl start minio
    
    # Wait for service to be ready
    sleep 10
    
    if systemctl is-active --quiet minio; then
        log_success "MinIO service started successfully"
    else
        log_error "Failed to start MinIO service"
        systemctl status minio
        exit 1
    fi
}

# Verify installation
verify_installation() {
    log_action "Verifying installation..."
    
    # Check service status
    if systemctl is-active --quiet minio; then
        log_success "MinIO service is running"
    else
        log_error "MinIO service is not running"
        return 1
    fi
    
    # Check API endpoint
    local_ip=$(hostname -I | awk '{print $1}')
    if curl -f -s "http://$local_ip:$MINIO_PORT/minio/health/live" > /dev/null; then
        log_success "MinIO API is responding"
    else
        log_warning "MinIO API is not responding (this may be normal during cluster formation)"
    fi
    
    # Display cluster information
    echo
    log_info "MinIO Cluster Information:"
    echo "Nodes: ${CLUSTER_NODES[*]}"
    echo "Drives per node: $DRIVES_PER_NODE"
    echo "Total drives: $((${#CLUSTER_NODES[@]} * DRIVES_PER_NODE))"
    echo "API Port: $MINIO_PORT"
    echo "Console Port: $MINIO_CONSOLE_PORT"
    echo "Data Directory: $MINIO_DATA_DIR"
    echo
    echo "Access URLs:"
    echo "API: http://$local_ip:$MINIO_PORT"
    echo "Console: http://$local_ip:$MINIO_CONSOLE_PORT"
    echo
    echo "Credentials:"
    echo "Username: $MINIO_ROOT_USER"
    echo "Password: $MINIO_ROOT_PASSWORD"
}

# Main installation function
main() {
    echo "============================================================"
    echo "MinIO Distributed Mode Installation"
    echo "============================================================"
    echo
    
    detect_os
    check_prerequisites
    install_dependencies
    create_user_and_directories
    install_minio
    generate_config
    create_systemd_service
    apply_optimizations
    configure_firewall
    start_minio
    verify_installation
    
    echo
    log_success "MinIO distributed mode installation completed!"
    echo
    log_info "Next steps:"
    echo "1. Repeat this installation on all cluster nodes"
    echo "2. Ensure all nodes can communicate on ports $MINIO_PORT and $MINIO_CONSOLE_PORT"
    echo "3. Access the MinIO Console at http://$local_ip:$MINIO_CONSOLE_PORT"
    echo "4. Configure your applications to use the MinIO API"
    echo
    log_warning "Important: Save the credentials shown above in a secure location"
}

# Run main function
main "$@"
