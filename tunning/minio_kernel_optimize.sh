#!/bin/bash

# MinIO Performance Optimization Kernel Parameter Auto-Configuration Script
# Created: 2025-08-09
# Supported OS: Ubuntu, Debian, CentOS, RHEL, Rocky Linux, AlmaLinux
# Purpose: Kernel parameter optimization for MinIO clusters

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

# Global variables
BACKUP_DIR="/etc/sysctl.d/backup"
SYSCTL_FILE="/etc/sysctl.d/99-minio-performance.conf"
LIMITS_FILE="/etc/security/limits.d/99-minio-performance.conf"
SYSTEMD_CONF="/etc/systemd/system.conf.d/99-minio-performance.conf"
DRY_RUN=false
FORCE=false

# Usage information
usage() {
    echo "MinIO Performance Optimization Kernel Parameter Configuration Script"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -d, --dry-run     Execute preview only without actual changes"
    echo "  -f, --force       Force execution without confirmation"
    echo "  -r, --restore     Restore settings from backup"
    echo "  -c, --check       Check current settings"
    echo "  -h, --help        Show this help message"
    echo
    echo "Examples:"
    echo "  $0                # Run optimization in interactive mode"
    echo "  $0 --dry-run      # Preview changes"
    echo "  $0 --force        # Apply immediately without confirmation"
    echo "  $0 --check        # Check current configuration status"
    echo "  $0 --restore      # Restore from backup"
}

# OS detection
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        OS_VERSION=$(cat /etc/redhat-release | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    else
        log_error "Unsupported operating system."
        exit 1
    fi
    
    case $OS in
        ubuntu|debian)
            OS_FAMILY="debian"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            OS_FAMILY="redhat"
            ;;
        *)
            log_warning "Unknown OS: $OS. Assuming RedHat family."
            OS_FAMILY="redhat"
            ;;
    esac
    
    log_info "Detected OS: $OS $OS_VERSION ($OS_FAMILY family)"
}

# Check privileges
check_privileges() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script requires root privileges."
        log_info "Please run with: sudo $0 $*"
        exit 1
    fi
}

# Create backup directory
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log_info "Created backup directory: $BACKUP_DIR"
    fi
}

# Backup current settings
backup_current_settings() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    create_backup_dir
    
    # Backup sysctl settings
    if [ -f "$SYSCTL_FILE" ]; then
        cp "$SYSCTL_FILE" "$BACKUP_DIR/sysctl_${timestamp}.conf"
        log_info "Backed up existing sysctl settings: $BACKUP_DIR/sysctl_${timestamp}.conf"
    fi
    
    # Backup limits settings
    if [ -f "$LIMITS_FILE" ]; then
        cp "$LIMITS_FILE" "$BACKUP_DIR/limits_${timestamp}.conf"
        log_info "Backed up existing limits settings: $BACKUP_DIR/limits_${timestamp}.conf"
    fi
    
    # Backup systemd settings
    if [ -f "$SYSTEMD_CONF" ]; then
        cp "$SYSTEMD_CONF" "$BACKUP_DIR/systemd_${timestamp}.conf"
        log_info "Backed up existing systemd settings: $BACKUP_DIR/systemd_${timestamp}.conf"
    fi
    
    # Save current kernel parameter values
    sysctl -a > "$BACKUP_DIR/current_sysctl_${timestamp}.txt" 2>/dev/null
    log_info "Backed up current kernel parameters: $BACKUP_DIR/current_sysctl_${timestamp}.txt"
}

# Check if parameter needs to be changed (with minimum value logic)
needs_change() {
    local param="$1"
    local new_value="$2"
    local is_minimum="${3:-false}"  # Third parameter indicates if this is a minimum value check
    
    local current_value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
    
    if [ "$current_value" = "N/A" ]; then
        return 0  # Needs change (parameter doesn't exist)
    fi
    
    # For minimum value parameters, don't change if current value is already higher
    if [ "$is_minimum" = "true" ]; then
        # Handle numeric comparison for minimum values
        if [ "$current_value" -ge "$new_value" ] 2>/dev/null; then
            return 1  # No change needed (current value is already sufficient)
        else
            return 0  # Needs change (current value is too low)
        fi
    else
        # For exact value parameters, change only if values don't match
        if [ "$current_value" = "$new_value" ]; then
            return 1  # No change needed
        else
            return 0  # Needs change
        fi
    fi
}

# Enhanced table format comparison output with minimum value logic
print_comparison_table_enhanced() {
    local title="$1"
    local -n params_ref=$2
    
    echo -e "${CYAN}[$title]${NC}"
    printf "%-40s | %-20s | %-20s | %-10s\n" "Parameter" "Current Value" "New Value" "Status"
    printf "%-40s-+-%-20s-+-%-20s-+-%-10s\n" "----------------------------------------" "--------------------" "--------------------" "----------"
    
    for param_info in "${params_ref[@]}"; do
        local param=$(echo "$param_info" | cut -d: -f1)
        local new_value=$(echo "$param_info" | cut -d: -f2)
        local description=$(echo "$param_info" | cut -d: -f3)
        local param_type=$(echo "$param_info" | cut -d: -f4)
        
        local current_value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
        
        # Determine status with minimum/maximum value logic
        local status=""
        if [ "$current_value" = "N/A" ]; then
            status="NEW"
        elif [ "$param_type" = "min" ]; then
            # For minimum value parameters
            if [ "$current_value" -ge "$new_value" ] 2>/dev/null; then
                status="OPTIMAL"  # Current value is already sufficient or better
            else
                status="CHANGE"   # Current value is too low
            fi
        elif [ "$param_type" = "max" ]; then
            # For maximum value parameters
            if [ "$current_value" -le "$new_value" ] 2>/dev/null; then
                status="OPTIMAL"  # Current value is within acceptable range
            else
                status="CHANGE"   # Current value is too high
            fi
        else
            # For exact value parameters
            if [ "$current_value" = "$new_value" ]; then
                status="SAME"
            else
                status="CHANGE"
            fi
        fi
        
        printf "%-40s | %-20s | %-20s | " "$param" "$current_value" "$new_value"
        
        # Print colored status
        if [ "$status" = "NEW" ]; then
            echo -e "${YELLOW}NEW${NC}"
        elif [ "$status" = "SAME" ]; then
            echo -e "${GREEN}SAME${NC}"
        elif [ "$status" = "OPTIMAL" ]; then
            echo -e "${GREEN}OPTIMAL${NC}"
        else
            echo -e "${RED}CHANGE${NC}"
        fi
    done
    echo
}

# Check if parameter needs to be changed (enhanced version)
needs_change_enhanced() {
    local param="$1"
    local new_value="$2"
    local param_type="${3:-exact}"
    
    local current_value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
    
    if [ "$current_value" = "N/A" ]; then
        return 0  # Needs change
    fi
    
    case "$param_type" in
        "min")
            # For minimum value parameters, don't change if current >= recommended
            if [ "$current_value" -ge "$new_value" ] 2>/dev/null; then
                return 1  # No change needed (current value is sufficient or better)
            else
                return 0  # Needs change (current value is too low)
            fi
            ;;
        "max")
            # For maximum value parameters, don't change if current <= recommended
            if [ "$current_value" -le "$new_value" ] 2>/dev/null; then
                return 1  # No change needed (current value is within limit)
            else
                return 0  # Needs change (current value is too high)
            fi
            ;;
        "exact"|*)
            # For exact value parameters
            if [ "$current_value" = "$new_value" ]; then
                return 1  # No change needed
            else
                return 0  # Needs change
            fi
            ;;
    esac
}

# Check if system limits need to be changed
limits_need_change() {
    local current_soft_nofile=$(ulimit -Sn)
    local current_hard_nofile=$(ulimit -Hn)
    local current_soft_nproc=$(ulimit -Su)
    local current_hard_nproc=$(ulimit -Hu)
    local current_soft_memlock=$(ulimit -Sl)
    local current_hard_memlock=$(ulimit -Hl)
    local current_soft_core=$(ulimit -Sc)
    local current_hard_core=$(ulimit -Hc)
    
    # Check if any limits need to be changed
    if [ "$current_soft_nofile" != "1048576" ] || [ "$current_hard_nofile" != "1048576" ] || \
       [ "$current_soft_nproc" != "1048576" ] || [ "$current_hard_nproc" != "1048576" ] || \
       [ "$current_soft_memlock" != "unlimited" ] || [ "$current_hard_memlock" != "unlimited" ] || \
       [ "$current_soft_core" != "unlimited" ] || [ "$current_hard_core" != "unlimited" ]; then
        return 0  # Needs change
    else
        return 1  # No change needed
    fi
}

# Check if systemd settings need to be changed
systemd_needs_change() {
    local systemd_params=(
        "DefaultLimitNOFILE:1048576"
        "DefaultLimitNPROC:1048576"
        "DefaultLimitMEMLOCK:infinity"
        "DefaultLimitCORE:infinity"
    )
    
    for param_info in "${systemd_params[@]}"; do
        local param=$(echo "$param_info" | cut -d: -f1)
        local new_value=$(echo "$param_info" | cut -d: -f2)
        
        local current_value="N/A"
        if systemctl show --property="$param" > /dev/null 2>&1; then
            current_value=$(systemctl show --property="$param" --value 2>/dev/null || echo "N/A")
        fi
        
        if [ "$current_value" = "N/A" ] || [ "$current_value" != "$new_value" ]; then
            return 0  # Needs change
        fi
    done
    
    return 1  # No change needed
}

# Check if I/O scheduler needs to be changed
io_scheduler_needs_change() {
    local grub_file=""
    if [ -f "/etc/default/grub" ]; then
        grub_file="/etc/default/grub"
    elif [ -f "/etc/sysconfig/grub" ]; then
        grub_file="/etc/sysconfig/grub"
    else
        return 0  # Needs change (no GRUB file found)
    fi
    
    local current_cmdline=""
    if [ -f "$grub_file" ]; then
        current_cmdline=$(grep "GRUB_CMDLINE_LINUX=" "$grub_file" | head -1 | cut -d= -f2- | tr -d '"' || echo "(not set)")
    else
        return 0  # Needs change
    fi
    
    if [[ "$current_cmdline" == *"elevator=none"* ]]; then
        return 1  # No change needed
    else
        return 0  # Needs change
    fi
}

# Generate optimized sysctl parameters only for parameters that need changes (enhanced)
get_optimized_sysctl_params_conditional() {
    local header_written=false
    
    # Network performance optimization parameters
    local network_params=(
        "net.core.rmem_default:262144:exact"
        "net.core.rmem_max:134217728:min"
        "net.core.wmem_default:262144:exact"
        "net.core.wmem_max:134217728:min"
        "net.core.netdev_max_backlog:30000:min"
        "net.core.netdev_budget:600:exact"
    )
    
    # TCP optimization parameters
    local tcp_params=(
        "net.ipv4.tcp_congestion_control:bbr:exact"
        "net.ipv4.tcp_mtu_probing:1:exact"
        "net.ipv4.tcp_window_scaling:1:exact"
        "net.ipv4.tcp_timestamps:1:exact"
        "net.ipv4.tcp_sack:1:exact"
        "net.ipv4.tcp_no_metrics_save:1:exact"
        "net.ipv4.tcp_moderate_rcvbuf:1:exact"
        "net.ipv4.tcp_slow_start_after_idle:0:exact"
    )
    
    # Connection management parameters (some timeouts are maximum values)
    local connection_params=(
        "net.ipv4.tcp_max_syn_backlog:65536:min"
        "net.core.somaxconn:65536:min"
        "net.ipv4.tcp_fin_timeout:30:max"
        "net.ipv4.tcp_keepalive_time:600:max"
        "net.ipv4.tcp_keepalive_intvl:60:max"
        "net.ipv4.tcp_keepalive_probes:3:max"
    )
    
    # Memory management parameters (some are maximum values)
    local memory_params=(
        "vm.dirty_ratio:5:max"
        "vm.dirty_background_ratio:2:max"
        "vm.dirty_expire_centisecs:3000:exact"
        "vm.dirty_writeback_centisecs:500:exact"
        "vm.swappiness:1:max"
        "vm.vfs_cache_pressure:50:max"
    )
    
    # Filesystem parameters (these are minimum values)
    local filesystem_params=(
        "fs.file-max:1048576:min"
        "fs.nr_open:1048576:min"
    )
    
    # Kernel performance parameters (these are minimum values)
    local kernel_params=(
        "kernel.pid_max:4194304:min"
        "kernel.threads-max:4194304:min"
    )
    
    # Virtual memory parameters
    local vm_params=(
        "vm.max_map_count:262144:min"
        "vm.overcommit_memory:1:exact"
    )
    
    # TCP buffer parameters (special handling)
    local tcp_buffer_params=(
        "net.ipv4.tcp_rmem:4096 87380 134217728:exact"
        "net.ipv4.tcp_wmem:4096 65536 134217728:exact"
    )
    
    # Combine all parameter arrays
    local all_params=(
        "${network_params[@]}" "${tcp_params[@]}" "${connection_params[@]}"
        "${memory_params[@]}" "${filesystem_params[@]}" "${kernel_params[@]}" "${vm_params[@]}"
    )
    
    # Check each parameter and only include those that need changes
    for param_info in "${all_params[@]}"; do
        local param=$(echo "$param_info" | cut -d: -f1)
        local new_value=$(echo "$param_info" | cut -d: -f2)
        local param_type=$(echo "$param_info" | cut -d: -f3)
        
        if needs_change_enhanced "$param" "$new_value" "$param_type"; then
            if [ "$header_written" = false ]; then
                echo "# MinIO performance optimization kernel parameters"
                echo "# Created: $(date)"
                echo "# Only parameters that need changes are included"
                echo ""
                header_written=true
            fi
            echo "$param = $new_value"
        fi
    done
    
    # Handle TCP buffer parameters separately (they have different format)
    for param_info in "${tcp_buffer_params[@]}"; do
        local param=$(echo "$param_info" | cut -d: -f1)
        local new_value=$(echo "$param_info" | cut -d: -f2-)
        local current_value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
        
        if [ "$current_value" = "N/A" ] || [ "$current_value" != "$new_value" ]; then
            if [ "$header_written" = false ]; then
                echo "# MinIO performance optimization kernel parameters"
                echo "# Created: $(date)"
                echo "# Only parameters that need changes are included"
                echo ""
                header_written=true
            fi
            echo "$param = $new_value"
        fi
    done
}

# System limits configuration
get_optimized_limits() {
    cat << 'EOF'
# MinIO performance optimization system limits
# Created: $(date)

# File descriptor limits for all users
* soft nofile 1048576
* hard nofile 1048576

# Process count limits
* soft nproc 1048576
* hard nproc 1048576

# Memory lock limits (unlimited)
* soft memlock unlimited
* hard memlock unlimited

# Core dump size
* soft core unlimited
* hard core unlimited

# Special settings for MinIO user (if exists)
minio soft nofile 1048576
minio hard nofile 1048576
minio soft nproc 1048576
minio hard nproc 1048576
EOF
}

# systemd configuration
get_optimized_systemd() {
    cat << 'EOF'
# MinIO performance optimization systemd configuration
# Created: $(date)

[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
DefaultLimitMEMLOCK=infinity
DefaultLimitCORE=infinity
EOF
}
# Table format comparison output
print_comparison_table() {
    local title="$1"
    local -n params_ref=$2
    
    echo -e "${CYAN}[$title]${NC}"
    printf "%-40s | %-20s | %-20s | %-10s\n" "Parameter" "Current Value" "New Value" "Status"
    printf "%-40s-+-%-20s-+-%-20s-+-%-10s\n" "----------------------------------------" "--------------------" "--------------------" "----------"
    
    for param_info in "${params_ref[@]}"; do
        local param=$(echo "$param_info" | cut -d: -f1)
        local new_value=$(echo "$param_info" | cut -d: -f2)
        local description=$(echo "$param_info" | cut -d: -f3)
        
        local current_value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
        
        # Determine status
        local status=""
        if [ "$current_value" = "N/A" ]; then
            status="NEW"
        elif [ "$current_value" = "$new_value" ]; then
            status="SAME"
        else
            status="CHANGE"
        fi
        
        printf "%-40s | %-20s | %-20s | " "$param" "$current_value" "$new_value"
        
        # Print colored status
        if [ "$status" = "NEW" ]; then
            echo -e "${YELLOW}NEW${NC}"
        elif [ "$status" = "SAME" ]; then
            echo -e "${GREEN}SAME${NC}"
        else
            echo -e "${RED}CHANGE${NC}"
        fi
    done
    echo
}

# System limits comparison table output
print_limits_comparison_table() {
    echo -e "${CYAN}[System Limits Comparison]${NC}"
    printf "%-25s | %-15s | %-15s | %-15s | %-10s\n" "Limit Type" "Current Soft" "Current Hard" "New Value" "Status"
    printf "%-25s-+-%-15s-+-%-15s-+-%-15s-+-%-10s\n" "-------------------------" "---------------" "---------------" "---------------" "----------"
    
    # File descriptors
    local current_soft_nofile=$(ulimit -Sn)
    local current_hard_nofile=$(ulimit -Hn)
    local new_nofile="1048576"
    
    printf "%-25s | %-15s | %-15s | %-15s | " "File Descriptors (nofile)" "$current_soft_nofile" "$current_hard_nofile" "$new_nofile"
    if [ "$current_soft_nofile" = "$new_nofile" ] && [ "$current_hard_nofile" = "$new_nofile" ]; then
        echo -e "${GREEN}SAME${NC}"
    else
        echo -e "${RED}CHANGE${NC}"
    fi
    
    # Process count
    local current_soft_nproc=$(ulimit -Su)
    local current_hard_nproc=$(ulimit -Hu)
    local new_nproc="1048576"
    
    printf "%-25s | %-15s | %-15s | %-15s | " "Processes (nproc)" "$current_soft_nproc" "$current_hard_nproc" "$new_nproc"
    if [ "$current_soft_nproc" = "$new_nproc" ] && [ "$current_hard_nproc" = "$new_nproc" ]; then
        echo -e "${GREEN}SAME${NC}"
    else
        echo -e "${RED}CHANGE${NC}"
    fi
    
    # Memory lock
    local current_soft_memlock=$(ulimit -Sl)
    local current_hard_memlock=$(ulimit -Hl)
    local new_memlock="unlimited"
    
    printf "%-25s | %-15s | %-15s | %-15s | " "Memory Lock (memlock)" "$current_soft_memlock" "$current_hard_memlock" "$new_memlock"
    if [ "$current_soft_memlock" = "unlimited" ] && [ "$current_hard_memlock" = "unlimited" ]; then
        echo -e "${GREEN}SAME${NC}"
    else
        echo -e "${RED}CHANGE${NC}"
    fi
    
    # Core dump
    local current_soft_core=$(ulimit -Sc)
    local current_hard_core=$(ulimit -Hc)
    local new_core="unlimited"
    
    printf "%-25s | %-15s | %-15s | %-15s | " "Core Dump (core)" "$current_soft_core" "$current_hard_core" "$new_core"
    if [ "$current_soft_core" = "unlimited" ] && [ "$current_hard_core" = "unlimited" ]; then
        echo -e "${GREEN}SAME${NC}"
    else
        echo -e "${RED}CHANGE${NC}"
    fi
    
    echo
}

# systemd settings comparison table output
print_systemd_comparison_table() {
    echo -e "${CYAN}[systemd Default Limits Comparison]${NC}"
    printf "%-30s | %-20s | %-20s | %-10s\n" "systemd Setting" "Current Value" "New Value" "Status"
    printf "%-30s-+-%-20s-+-%-20s-+-%-10s\n" "------------------------------" "--------------------" "--------------------" "----------"
    
    local systemd_params=(
        "DefaultLimitNOFILE:1048576"
        "DefaultLimitNPROC:1048576"
        "DefaultLimitMEMLOCK:infinity"
        "DefaultLimitCORE:infinity"
    )
    
    for param_info in "${systemd_params[@]}"; do
        local param=$(echo "$param_info" | cut -d: -f1)
        local new_value=$(echo "$param_info" | cut -d: -f2)
        
        local current_value="N/A"
        if systemctl show --property="$param" > /dev/null 2>&1; then
            current_value=$(systemctl show --property="$param" --value 2>/dev/null || echo "N/A")
        fi
        
        printf "%-30s | %-20s | %-20s | " "$param" "$current_value" "$new_value"
        
        # Print colored status
        if [ "$current_value" = "N/A" ]; then
            echo -e "${YELLOW}UNKNOWN${NC}"
        elif [ "$current_value" = "$new_value" ]; then
            echo -e "${GREEN}SAME${NC}"
        else
            echo -e "${RED}CHANGE${NC}"
        fi
    done
    echo
}
# Check current settings
check_current_settings() {
    log_info "Checking current kernel parameter settings"
    echo "=================================================="
    
    # Check key parameters
    local params=(
        "net.core.rmem_max"
        "net.core.wmem_max"
        "vm.dirty_ratio"
        "vm.swappiness"
        "fs.file-max"
        "net.ipv4.tcp_congestion_control"
    )
    
    for param in "${params[@]}"; do
        current_value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
        echo "$param = $current_value"
    done
    
    echo
    log_info "Current system limits"
    echo "File descriptor limit (soft): $(ulimit -Sn)"
    echo "File descriptor limit (hard): $(ulimit -Hn)"
    echo "Process count limit (soft): $(ulimit -Su)"
    echo "Process count limit (hard): $(ulimit -Hu)"
    
    echo
    log_info "Configuration file existence"
    [ -f "$SYSCTL_FILE" ] && echo "✓ $SYSCTL_FILE" || echo "✗ $SYSCTL_FILE"
    [ -f "$LIMITS_FILE" ] && echo "✓ $LIMITS_FILE" || echo "✗ $LIMITS_FILE"
    [ -f "$SYSTEMD_CONF" ] && echo "✓ $SYSTEMD_CONF" || echo "✗ $SYSTEMD_CONF"
    
    echo "=================================================="
}

# I/O scheduler configuration
configure_io_scheduler() {
    log_info "I/O scheduler optimization configuration"
    
    # Find GRUB configuration file
    local grub_file=""
    if [ -f "/etc/default/grub" ]; then
        grub_file="/etc/default/grub"
    elif [ -f "/etc/sysconfig/grub" ]; then
        grub_file="/etc/sysconfig/grub"
    else
        log_info "GRUB configuration file not found."
        log_info "Typically located at:"
        log_info "- Ubuntu/Debian: /etc/default/grub"
        log_info "- RedHat Family: /etc/sysconfig/grub"
        return 1
    fi
    
    # Check if I/O scheduler needs to be changed
    local io_changes_needed=false
    if io_scheduler_needs_change; then
        io_changes_needed=true
    fi
    
    echo
    echo -e "${CYAN}[I/O Scheduler Configuration Comparison]${NC}"
    printf "%-25s | %-30s | %-20s | %-12s\n" "Configuration Item" "Current Value" "New Value" "Status"
    printf "%-25s-+-%-30s-+-%-20s-+-%-12s\n" "-------------------------" "------------------------------" "--------------------" "------------"
    
    # GRUB file location
    printf "%-25s | %-30s | %-20s | " "GRUB Config File" "$grub_file" "$grub_file"
    echo -e "${GREEN}SAME${NC}"
    
    # Current GRUB_CMDLINE_LINUX setting
    local current_cmdline=""
    if [ -f "$grub_file" ]; then
        current_cmdline=$(grep "GRUB_CMDLINE_LINUX=" "$grub_file" | head -1 | cut -d= -f2- | tr -d '"' || echo "(not set)")
    else
        current_cmdline="(file not found)"
    fi
    
    local new_cmdline="elevator=none"
    printf "%-25s | %-30s | %-20s | " "I/O Scheduler" 
    if [[ "$current_cmdline" == *"elevator=none"* ]]; then
        printf "%-30s | %-20s | " "none (already set)" "none"
        echo -e "${GREEN}SAME${NC}"
    elif [[ "$current_cmdline" == *"elevator="* ]]; then
        local current_elevator=$(echo "$current_cmdline" | grep -o 'elevator=[^ ]*' | cut -d= -f2)
        printf "%-30s | %-20s | " "$current_elevator" "none"
        echo -e "${RED}CHANGE${NC}"
    else
        printf "%-30s | %-20s | " "(not set)" "none"
        echo -e "${YELLOW}NEW${NC}"
    fi
    
    # Check currently running I/O schedulers
    local current_schedulers=""
    for device in /sys/block/*/queue/scheduler; do
        if [ -f "$device" ]; then
            local dev_name=$(echo "$device" | cut -d/ -f4)
            local scheduler=$(cat "$device" | grep -o '\[.*\]' | tr -d '[]' || echo "unknown")
            if [ -n "$current_schedulers" ]; then
                current_schedulers="$current_schedulers, $dev_name:$scheduler"
            else
                current_schedulers="$dev_name:$scheduler"
            fi
        fi
    done
    
    if [ -n "$current_schedulers" ]; then
        printf "%-25s | %-30s | %-20s | " "Active Schedulers" "$current_schedulers" "none (after reboot)"
        echo -e "${YELLOW}REBOOT_REQ${NC}"
    fi
    
    echo
    
    # Check GRUB update commands
    echo -e "${CYAN}[GRUB Update Commands]${NC}"
    if command -v update-grub > /dev/null; then
        echo "Ubuntu/Debian: update-grub"
    elif command -v grub2-mkconfig > /dev/null; then
        echo "RedHat Family: grub2-mkconfig -o /boot/grub2/grub.cfg"
    else
        echo "GRUB update command not found"
    fi
    echo
    
    if $DRY_RUN; then
        if [ "$io_changes_needed" = true ]; then
            log_info "[DRY RUN] I/O scheduler changes are needed"
            log_info "[DRY RUN] Change Summary:"
            echo "1. Add 'elevator=none' to GRUB configuration"
            echo "2. Remove existing elevator settings if present"
            echo "3. Update GRUB configuration"
            echo "4. I/O scheduler changes will take effect after reboot"
        else
            log_success "[DRY RUN] I/O scheduler is already optimized - no changes needed"
        fi
        echo
        return 0
    fi
    
    if [ "$io_changes_needed" = false ]; then
        log_success "I/O scheduler is already optimized - no changes needed"
        return 0
    fi
    
    # Check current GRUB configuration
    if grep -q "elevator=" "$grub_file"; then
        log_info "Existing I/O scheduler configuration found."
        if ! $FORCE; then
            read -p "Change I/O scheduler to 'none'? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Skipping I/O scheduler configuration."
                return 0
            fi
        fi
    fi
    
    # Backup GRUB configuration
    cp "$grub_file" "$grub_file.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add/modify I/O scheduler setting
    if grep -q "GRUB_CMDLINE_LINUX=" "$grub_file"; then
        # Remove existing elevator settings
        sed -i 's/elevator=[^ ]*//g' "$grub_file"
        # Add new setting
        sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="elevator=none /' "$grub_file"
    else
        echo 'GRUB_CMDLINE_LINUX="elevator=none"' >> "$grub_file"
    fi
    
    # Update GRUB
    if command -v update-grub > /dev/null; then
        update-grub
        log_success "GRUB configuration updated (Ubuntu/Debian)"
    elif command -v grub2-mkconfig > /dev/null; then
        if [ "$OS_FAMILY" = "redhat" ]; then
            grub2-mkconfig -o /boot/grub2/grub.cfg
            log_success "GRUB configuration updated (RedHat Family)"
        fi
    else
        log_warning "GRUB update command not found. Please update manually."
    fi
    
    log_warning "I/O scheduler changes will take effect after reboot."
}

# Apply kernel parameter settings
apply_sysctl_settings() {
    log_action "Applying kernel parameter optimization settings"
    
    # Network performance optimization parameters (with type indicators)
    local network_params=(
        "net.core.rmem_default:262144:Default receive buffer size:exact"
        "net.core.rmem_max:134217728:Maximum receive buffer size:min"
        "net.core.wmem_default:262144:Default send buffer size:exact"
        "net.core.wmem_max:134217728:Maximum send buffer size:min"
        "net.core.netdev_max_backlog:30000:Network backlog queue size:min"
        "net.core.netdev_budget:600:Network processing budget:exact"
    )
    
    # TCP optimization parameters
    local tcp_params=(
        "net.ipv4.tcp_congestion_control:bbr:TCP congestion control algorithm:exact"
        "net.ipv4.tcp_mtu_probing:1:Enable MTU probing:exact"
        "net.ipv4.tcp_window_scaling:1:Enable window scaling:exact"
        "net.ipv4.tcp_timestamps:1:Enable timestamps:exact"
        "net.ipv4.tcp_sack:1:Enable selective acknowledgment:exact"
        "net.ipv4.tcp_slow_start_after_idle:0:Disable slow start after idle:exact"
    )
    
    # Connection management parameters (some timeouts are maximum values)
    local connection_params=(
        "net.ipv4.tcp_max_syn_backlog:65536:SYN backlog queue size:min"
        "net.core.somaxconn:65536:Socket connection queue size:min"
        "net.ipv4.tcp_fin_timeout:30:FIN timeout:max"
        "net.ipv4.tcp_keepalive_time:600:Keepalive time:max"
        "net.ipv4.tcp_keepalive_intvl:60:Keepalive interval:max"
        "net.ipv4.tcp_keepalive_probes:3:Keepalive probe count:max"
    )
    
    # Memory management parameters (some are maximum values)
    local memory_params=(
        "vm.dirty_ratio:5:Dirty page ratio:max"
        "vm.dirty_background_ratio:2:Background dirty page ratio:max"
        "vm.dirty_expire_centisecs:3000:Dirty page expiration time:exact"
        "vm.dirty_writeback_centisecs:500:Dirty page writeback interval:exact"
        "vm.swappiness:1:Swap usage tendency:max"
        "vm.vfs_cache_pressure:50:VFS cache pressure:max"
    )
    
    # Filesystem parameters (minimum values - don't change if current is higher)
    local filesystem_params=(
        "fs.file-max:1048576:System maximum file descriptors:min"
        "fs.nr_open:1048576:Per-process maximum file descriptors:min"
    )
    
    # Kernel performance parameters (minimum values)
    local kernel_params=(
        "kernel.pid_max:4194304:Maximum process ID:min"
        "kernel.threads-max:4194304:Maximum thread count:min"
    )
    
    # Virtual memory parameters
    local vm_params=(
        "vm.max_map_count:262144:Maximum memory map areas:min"
        "vm.overcommit_memory:1:Memory overcommit policy:exact"
    )
    
    # Check if any kernel parameters need changes (using enhanced logic)
    local kernel_changes_needed=false
    local all_params=(
        "${network_params[@]}" "${tcp_params[@]}" "${connection_params[@]}"
        "${memory_params[@]}" "${filesystem_params[@]}" "${kernel_params[@]}" "${vm_params[@]}"
    )
    
    for param_info in "${all_params[@]}"; do
        local param=$(echo "$param_info" | cut -d: -f1)
        local new_value=$(echo "$param_info" | cut -d: -f2)
        local param_type=$(echo "$param_info" | cut -d: -f4)
        
        if needs_change_enhanced "$param" "$new_value" "$param_type"; then
            kernel_changes_needed=true
            break
        fi
    done
    
    # Also check TCP buffer parameters
    local tcp_buffer_params=(
        "net.ipv4.tcp_rmem:4096 87380 134217728"
        "net.ipv4.tcp_wmem:4096 65536 134217728"
    )
    
    for param_info in "${tcp_buffer_params[@]}"; do
        local param=$(echo "$param_info" | cut -d: -f1)
        local new_value=$(echo "$param_info" | cut -d: -f2-)
        local current_value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
        
        if [ "$current_value" = "N/A" ] || [ "$current_value" != "$new_value" ]; then
            kernel_changes_needed=true
            break
        fi
    done
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Configuration file location: $SYSCTL_FILE"
        if [ "$kernel_changes_needed" = true ]; then
            log_info "[DRY RUN] Kernel parameter changes are needed"
        else
            log_success "[DRY RUN] All kernel parameters are already optimized - no changes needed"
        fi
        echo
    else
        log_info "Configuration file location: $SYSCTL_FILE"
        if [ "$kernel_changes_needed" = true ]; then
            log_info "Kernel parameter changes are needed"
            
            # Create directory
            mkdir -p "$(dirname "$SYSCTL_FILE")"
            
            # Create configuration file with only parameters that need changes
            get_optimized_sysctl_params_conditional > "$SYSCTL_FILE"
        else
            log_success "All kernel parameters are already optimized - no changes needed"
            echo
            return 0
        fi
        echo
    fi
    
    # Display comparison tables (both dry-run and actual execution)
    print_comparison_table_enhanced "Network Performance Optimization" network_params
    print_comparison_table_enhanced "TCP Optimization" tcp_params
    print_comparison_table_enhanced "Connection Management" connection_params
    print_comparison_table_enhanced "Memory Management" memory_params
    print_comparison_table_enhanced "Filesystem" filesystem_params
    print_comparison_table_enhanced "Kernel Performance" kernel_params
    print_comparison_table_enhanced "Virtual Memory" vm_params
    
    # Summary statistics (using enhanced logic)
    local total_params=$(echo "${all_params[@]}" | wc -w)
    local changed_params=0
    local same_params=0
    local optimal_params=0
    
    # Check change status of key parameters
    for param_info in "${all_params[@]}"; do
        local param=$(echo "$param_info" | cut -d: -f1)
        local new_value=$(echo "$param_info" | cut -d: -f2)
        local param_type=$(echo "$param_info" | cut -d: -f4)
        local current_value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
        
        if [ "$current_value" = "N/A" ]; then
            changed_params=$((changed_params + 1))
        elif [ "$param_type" = "min" ]; then
            if [ "$current_value" -ge "$new_value" ] 2>/dev/null; then
                optimal_params=$((optimal_params + 1))
            else
                changed_params=$((changed_params + 1))
            fi
        elif [ "$param_type" = "max" ]; then
            if [ "$current_value" -le "$new_value" ] 2>/dev/null; then
                optimal_params=$((optimal_params + 1))
            else
                changed_params=$((changed_params + 1))
            fi
        else
            if [ "$current_value" = "$new_value" ]; then
                same_params=$((same_params + 1))
            else
                changed_params=$((changed_params + 1))
            fi
        fi
    done
    
    # Add TCP buffer parameters to count
    for param_info in "${tcp_buffer_params[@]}"; do
        local param=$(echo "$param_info" | cut -d: -f1)
        local new_value=$(echo "$param_info" | cut -d: -f2-)
        local current_value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
        
        total_params=$((total_params + 1))
        if [ "$current_value" != "$new_value" ]; then
            changed_params=$((changed_params + 1))
        else
            same_params=$((same_params + 1))
        fi
    done
    
    echo -e "${BLUE}[Summary Statistics]${NC}"
    printf "%-20s | %-10s\n" "Category" "Count"
    printf "%-20s-+-%-10s\n" "--------------------" "----------"
    printf "%-20s | %-10s\n" "Total Parameters" "$total_params"
    printf "%-20s | %-10s\n" "Need Changes" "$changed_params"
    printf "%-20s | %-10s\n" "Already Optimal" "$((same_params + optimal_params))"
    echo
    
    # Apply actual settings only if changes are needed
    if ! $DRY_RUN && [ "$kernel_changes_needed" = true ]; then
        if [ -f "$SYSCTL_FILE" ] && sysctl -p "$SYSCTL_FILE" > /dev/null 2>&1; then
            log_success "Kernel parameters have been successfully applied."
        else
            log_error "Error occurred while applying kernel parameters."
            return 1
        fi
    elif ! $DRY_RUN; then
        log_info "No kernel parameter changes were applied (all already optimized)."
    fi
}
# Apply system limits settings
apply_limits_settings() {
    log_action "Applying system limits settings"
    
    # Check if limits need to be changed
    local limits_changes_needed=false
    if limits_need_change; then
        limits_changes_needed=true
    fi
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Configuration file location: $LIMITS_FILE"
        if [ "$limits_changes_needed" = true ]; then
            log_info "[DRY RUN] System limits changes are needed"
        else
            log_success "[DRY RUN] All system limits are already optimized - no changes needed"
        fi
        echo
    else
        log_info "Configuration file location: $LIMITS_FILE"
        if [ "$limits_changes_needed" = true ]; then
            log_info "System limits changes are needed"
            
            # Create directory
            mkdir -p "$(dirname "$LIMITS_FILE")"
            
            # Create configuration file
            get_optimized_limits | sed "s/\$(date)/$(date)/" > "$LIMITS_FILE"
        else
            log_success "All system limits are already optimized - no changes needed"
            echo
            return 0
        fi
        echo
    fi
    
    # Display system limits comparison table (both dry-run and actual execution)
    print_limits_comparison_table
    
    # Configuration file preview (only if changes are needed or in dry-run mode)
    if [ "$limits_changes_needed" = true ] || $DRY_RUN; then
        echo -e "${CYAN}[Configuration File Preview]${NC}"
        echo "File Location: $LIMITS_FILE"
        echo "----------------------------------------"
        echo "# MinIO performance optimization system limits"
        echo ""
        echo "# File descriptor limits for all users"
        echo "* soft nofile 1048576"
        echo "* hard nofile 1048576"
        echo ""
        echo "# Process count limits"
        echo "* soft nproc 1048576"
        echo "* hard nproc 1048576"
        echo ""
        echo "# Memory lock limits (unlimited)"
        echo "* soft memlock unlimited"
        echo "* hard memlock unlimited"
        echo ""
        echo "# Core dump size"
        echo "* soft core unlimited"
        echo "* hard core unlimited"
        echo ""
        echo "# Special settings for MinIO user (if exists)"
        echo "minio soft nofile 1048576"
        echo "minio hard nofile 1048576"
        echo "minio soft nproc 1048576"
        echo "minio hard nproc 1048576"
        echo "----------------------------------------"
        echo
    fi
    
    if $DRY_RUN; then
        if [ "$limits_changes_needed" = true ]; then
            log_info "[DRY RUN] These settings will be applied when logging in to a new session."
            log_warning "[DRY RUN] Current session can be changed temporarily with 'ulimit' command."
        fi
    else
        if [ "$limits_changes_needed" = true ]; then
            log_success "System limits configuration has been applied: $LIMITS_FILE"
            log_info "These settings will be applied when logging in to a new session."
            log_warning "Current session can be changed temporarily with 'ulimit' command."
        else
            log_info "No system limits changes were applied (all already optimized)."
        fi
    fi
}

# Apply systemd settings
apply_systemd_settings() {
    log_action "Applying systemd settings"
    
    # Check if systemd settings need to be changed
    local systemd_changes_needed=false
    if systemd_needs_change; then
        systemd_changes_needed=true
    fi
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Configuration file location: $SYSTEMD_CONF"
        if [ "$systemd_changes_needed" = true ]; then
            log_info "[DRY RUN] systemd configuration changes are needed"
        else
            log_success "[DRY RUN] All systemd settings are already optimized - no changes needed"
        fi
        echo
    else
        log_info "Configuration file location: $SYSTEMD_CONF"
        if [ "$systemd_changes_needed" = true ]; then
            log_info "systemd configuration changes are needed"
            
            # Create directory
            mkdir -p "$(dirname "$SYSTEMD_CONF")"
            
            # Create configuration file
            get_optimized_systemd | sed "s/\$(date)/$(date)/" > "$SYSTEMD_CONF"
        else
            log_success "All systemd settings are already optimized - no changes needed"
            echo
            return 0
        fi
        echo
    fi
    
    # Display systemd settings comparison table (both dry-run and actual execution)
    print_systemd_comparison_table
    
    # Configuration file preview (only if changes are needed or in dry-run mode)
    if [ "$systemd_changes_needed" = true ] || $DRY_RUN; then
        echo -e "${CYAN}[Configuration File Preview]${NC}"
        echo "File Location: $SYSTEMD_CONF"
        echo "----------------------------------------"
        echo "# MinIO performance optimization systemd configuration"
        echo ""
        echo "[Manager]"
        echo "DefaultLimitNOFILE=1048576"
        echo "DefaultLimitNPROC=1048576"
        echo "DefaultLimitMEMLOCK=infinity"
        echo "DefaultLimitCORE=infinity"
        echo "----------------------------------------"
        echo
    fi
    
    if $DRY_RUN; then
        if [ "$systemd_changes_needed" = true ]; then
            log_info "[DRY RUN] These settings will be applied to newly started services after systemctl daemon-reload."
            log_info "[DRY RUN] Existing running services need to be restarted to apply new limits."
        fi
    else
        if [ "$systemd_changes_needed" = true ]; then
            # Reload systemd
            systemctl daemon-reload
            
            log_success "systemd configuration has been applied: $SYSTEMD_CONF"
            log_info "These settings will be applied to newly started services after systemctl daemon-reload."
            log_info "Existing running services need to be restarted to apply new limits."
        else
            log_info "No systemd configuration changes were applied (all already optimized)."
        fi
    fi
}

# Restore settings
restore_settings() {
    log_info "Starting settings restoration"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
    
    # Display available backup files
    echo "Available backup files:"
    ls -la "$BACKUP_DIR"
    
    echo
    read -p "Enter backup date to restore (YYYYMMDD_HHMMSS): " backup_date
    
    # Restore backup files
    local sysctl_backup="$BACKUP_DIR/sysctl_${backup_date}.conf"
    local limits_backup="$BACKUP_DIR/limits_${backup_date}.conf"
    local systemd_backup="$BACKUP_DIR/systemd_${backup_date}.conf"
    
    if [ -f "$sysctl_backup" ]; then
        cp "$sysctl_backup" "$SYSCTL_FILE"
        sysctl -p "$SYSCTL_FILE"
        log_success "sysctl settings have been restored."
    fi
    
    if [ -f "$limits_backup" ]; then
        cp "$limits_backup" "$LIMITS_FILE"
        log_success "limits settings have been restored."
    fi
    
    if [ -f "$systemd_backup" ]; then
        cp "$systemd_backup" "$SYSTEMD_CONF"
        systemctl daemon-reload
        log_success "systemd settings have been restored."
    fi
}

# Main optimization function
main_optimize() {
    log_info "Starting MinIO performance optimization"
    echo "=================================================="
    
    if $DRY_RUN; then
        log_warning "DRY RUN mode: No actual changes will be applied."
        echo
    fi
    
    # Display current settings
    check_current_settings
    
    if ! $FORCE && ! $DRY_RUN; then
        echo
        log_warning "This script will modify system kernel parameters."
        log_warning "Automatic backup will be created before changes."
        echo
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled."
            exit 0
        fi
    fi
    
    # Create backup
    if ! $DRY_RUN; then
        backup_current_settings
    else
        log_info "[DRY RUN] Backup will be created at: $BACKUP_DIR"
    fi
    
    echo
    # Apply optimizations
    apply_sysctl_settings
    echo
    apply_limits_settings
    echo
    apply_systemd_settings
    echo
    configure_io_scheduler
    
    echo
    echo "=================================================="
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Summary - Changes to be applied:"
        echo "1. Kernel parameters file: $SYSCTL_FILE"
        echo "   - Network performance optimization (buffer sizes, TCP settings)"
        echo "   - Memory management optimization (dirty ratio, swappiness)"
        echo "   - Filesystem optimization (file-max, nr_open)"
        echo "   - Kernel performance optimization (pid_max, threads-max)"
        echo
        echo "2. System limits file: $LIMITS_FILE"
        echo "   - File descriptor limits: 1048576"
        echo "   - Process count limits: 1048576"
        echo "   - Memory lock: unlimited"
        echo "   - Core dump: unlimited"
        echo
        echo "3. systemd configuration file: $SYSTEMD_CONF"
        echo "   - Default service limit values"
        echo
        echo "4. GRUB configuration modification"
        echo "   - Set I/O scheduler to 'none' (SSD optimization)"
        echo
        log_warning "[DRY RUN] To apply these changes, run without --dry-run option:"
        log_warning "[DRY RUN] sudo $0"
        echo
        log_info "[DRY RUN] Or to apply without confirmation:"
        log_info "[DRY RUN] sudo $0 --force"
    else
        log_success "MinIO performance optimization completed!"
        
        echo
        log_info "Applied configurations:"
        echo "- Kernel parameters: $SYSCTL_FILE"
        echo "- System limits: $LIMITS_FILE"
        echo "- systemd configuration: $SYSTEMD_CONF"
        echo
        log_warning "Some settings will take full effect after reboot."
        log_info "New login sessions will apply the limits settings."
        
        echo
        read -p "Reboot now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Rebooting system..."
            reboot
        fi
    fi
}

# Command line argument processing
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -r|--restore)
            ACTION="restore"
            shift
            ;;
        -c|--check)
            ACTION="check"
            shift
            ;;
        -h|--help)
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

# Main execution
detect_os

case "${ACTION:-optimize}" in
    check)
        check_current_settings
        ;;
    restore)
        check_privileges
        restore_settings
        ;;
    optimize)
        check_privileges
        main_optimize
        ;;
    *)
        log_error "Unknown action: $ACTION"
        usage
        exit 1
        ;;
esac
