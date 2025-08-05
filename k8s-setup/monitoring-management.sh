#!/bin/bash

# Monitoring Management Script for MinIO
# This script provides management operations for Prometheus and Grafana monitoring stack

set -e

MONITORING_NAMESPACE="monitoring"

# Function to show monitoring stack status
show_monitoring_status() {
    echo "Monitoring Stack Status"
    echo "======================="
    echo ""
    
    echo "Namespace Status:"
    kubectl get namespace $MONITORING_NAMESPACE 2>/dev/null || echo "Monitoring namespace not found"
    echo ""
    
    echo "Deployments:"
    kubectl get deployments -n $MONITORING_NAMESPACE 2>/dev/null || echo "No deployments found"
    echo ""
    
    echo "Pods:"
    kubectl get pods -n $MONITORING_NAMESPACE -o wide 2>/dev/null || echo "No pods found"
    echo ""
    
    echo "Services:"
    kubectl get svc -n $MONITORING_NAMESPACE 2>/dev/null || echo "No services found"
    echo ""
    
    echo "Persistent Volume Claims:"
    kubectl get pvc -n $MONITORING_NAMESPACE 2>/dev/null || echo "No PVCs found"
    echo ""
    
    # Check external access
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null)
    if [ -z "$NODE_IP" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    fi
    
    if [ ! -z "$NODE_IP" ]; then
        echo "Access URLs:"
        echo "- Prometheus: http://$NODE_IP:30090"
        echo "- Grafana: http://$NODE_IP:30300"
        echo "- AlertManager: http://$NODE_IP:30093"
    fi
}

# Function to check monitoring health
check_monitoring_health() {
    echo "Monitoring Health Check"
    echo "======================"
    echo ""
    
    # Check Prometheus
    echo "Prometheus Health:"
    if kubectl get deployment prometheus -n $MONITORING_NAMESPACE &>/dev/null; then
        PROMETHEUS_READY=$(kubectl get deployment prometheus -n $MONITORING_NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        PROMETHEUS_DESIRED=$(kubectl get deployment prometheus -n $MONITORING_NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        
        if [ "$PROMETHEUS_READY" = "$PROMETHEUS_DESIRED" ] && [ "$PROMETHEUS_READY" != "0" ]; then
            echo "✓ Prometheus is healthy ($PROMETHEUS_READY/$PROMETHEUS_DESIRED replicas ready)"
        else
            echo "✗ Prometheus is unhealthy ($PROMETHEUS_READY/$PROMETHEUS_DESIRED replicas ready)"
        fi
    else
        echo "✗ Prometheus deployment not found"
    fi
    
    # Check Grafana
    echo "Grafana Health:"
    if kubectl get deployment grafana -n $MONITORING_NAMESPACE &>/dev/null; then
        GRAFANA_READY=$(kubectl get deployment grafana -n $MONITORING_NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        GRAFANA_DESIRED=$(kubectl get deployment grafana -n $MONITORING_NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        
        if [ "$GRAFANA_READY" = "$GRAFANA_DESIRED" ] && [ "$GRAFANA_READY" != "0" ]; then
            echo "✓ Grafana is healthy ($GRAFANA_READY/$GRAFANA_DESIRED replicas ready)"
        else
            echo "✗ Grafana is unhealthy ($GRAFANA_READY/$GRAFANA_DESIRED replicas ready)"
        fi
    else
        echo "✗ Grafana deployment not found"
    fi
    
    # Check AlertManager
    echo "AlertManager Health:"
    if kubectl get deployment alertmanager -n $MONITORING_NAMESPACE &>/dev/null; then
        ALERTMANAGER_READY=$(kubectl get deployment alertmanager -n $MONITORING_NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        ALERTMANAGER_DESIRED=$(kubectl get deployment alertmanager -n $MONITORING_NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        
        if [ "$ALERTMANAGER_READY" = "$ALERTMANAGER_DESIRED" ] && [ "$ALERTMANAGER_READY" != "0" ]; then
            echo "✓ AlertManager is healthy ($ALERTMANAGER_READY/$ALERTMANAGER_DESIRED replicas ready)"
        else
            echo "✗ AlertManager is unhealthy ($ALERTMANAGER_READY/$ALERTMANAGER_DESIRED replicas ready)"
        fi
    else
        echo "✗ AlertManager deployment not found"
    fi
    
    # Check MinIO targets (if Prometheus is available)
    echo ""
    echo "MinIO Target Health:"
    if kubectl get pod -l app=prometheus -n $MONITORING_NAMESPACE &>/dev/null; then
        echo "Checking MinIO targets in Prometheus..."
        # This would require port-forwarding to check actual targets
        echo "ℹ Use 'kubectl port-forward svc/prometheus 9090:9090 -n monitoring' to check targets manually"
    else
        echo "✗ Cannot check MinIO targets - Prometheus not available"
    fi
}

# Function to restart monitoring components
restart_monitoring() {
    echo "Restarting Monitoring Components"
    echo "================================"
    echo ""
    
    read -p "Which component to restart? (prometheus/grafana/alertmanager/all): " component
    
    case $component in
        prometheus)
            echo "Restarting Prometheus..."
            kubectl rollout restart deployment/prometheus -n $MONITORING_NAMESPACE
            kubectl rollout status deployment/prometheus -n $MONITORING_NAMESPACE
            ;;
        grafana)
            echo "Restarting Grafana..."
            kubectl rollout restart deployment/grafana -n $MONITORING_NAMESPACE
            kubectl rollout status deployment/grafana -n $MONITORING_NAMESPACE
            ;;
        alertmanager)
            echo "Restarting AlertManager..."
            kubectl rollout restart deployment/alertmanager -n $MONITORING_NAMESPACE
            kubectl rollout status deployment/alertmanager -n $MONITORING_NAMESPACE
            ;;
        all)
            echo "Restarting all monitoring components..."
            kubectl rollout restart deployment/prometheus -n $MONITORING_NAMESPACE
            kubectl rollout restart deployment/grafana -n $MONITORING_NAMESPACE
            kubectl rollout restart deployment/alertmanager -n $MONITORING_NAMESPACE
            
            echo "Waiting for all components to be ready..."
            kubectl rollout status deployment/prometheus -n $MONITORING_NAMESPACE
            kubectl rollout status deployment/grafana -n $MONITORING_NAMESPACE
            kubectl rollout status deployment/alertmanager -n $MONITORING_NAMESPACE
            ;;
        *)
            echo "Invalid option. Please choose: prometheus, grafana, alertmanager, or all"
            return 1
            ;;
    esac
    
    echo "✓ Restart completed"
}

# Function to backup monitoring configuration
backup_monitoring_config() {
    echo "Backing up Monitoring Configuration"
    echo "==================================="
    echo ""
    
    BACKUP_DIR="/tmp/monitoring-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p $BACKUP_DIR
    
    echo "Creating backup in: $BACKUP_DIR"
    
    # Backup all monitoring resources
    kubectl get all -n $MONITORING_NAMESPACE -o yaml > $BACKUP_DIR/monitoring-resources.yaml
    kubectl get configmaps -n $MONITORING_NAMESPACE -o yaml > $BACKUP_DIR/monitoring-configmaps.yaml
    kubectl get secrets -n $MONITORING_NAMESPACE -o yaml > $BACKUP_DIR/monitoring-secrets.yaml
    kubectl get pvc -n $MONITORING_NAMESPACE -o yaml > $BACKUP_DIR/monitoring-pvcs.yaml
    
    echo "✓ Backup completed: $BACKUP_DIR"
    echo "Files created:"
    ls -la $BACKUP_DIR
}

# Function to update monitoring stack
update_monitoring() {
    echo "Updating Monitoring Stack"
    echo "========================="
    echo ""
    
    echo "Available update options:"
    echo "1. Update Prometheus image"
    echo "2. Update Grafana image"
    echo "3. Update AlertManager image"
    echo "4. Update all images"
    echo ""
    
    read -p "Select option (1-4): " choice
    
    case $choice in
        1)
            read -p "Enter new Prometheus image (e.g., prom/prometheus:v2.46.0): " new_image
            if [ ! -z "$new_image" ]; then
                kubectl patch deployment prometheus -n $MONITORING_NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"prometheus","image":"'$new_image'"}]}}}}'
                kubectl rollout status deployment/prometheus -n $MONITORING_NAMESPACE
            fi
            ;;
        2)
            read -p "Enter new Grafana image (e.g., grafana/grafana:10.1.0): " new_image
            if [ ! -z "$new_image" ]; then
                kubectl patch deployment grafana -n $MONITORING_NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"grafana","image":"'$new_image'"}]}}}}'
                kubectl rollout status deployment/grafana -n $MONITORING_NAMESPACE
            fi
            ;;
        3)
            read -p "Enter new AlertManager image (e.g., prom/alertmanager:v0.26.0): " new_image
            if [ ! -z "$new_image" ]; then
                kubectl patch deployment alertmanager -n $MONITORING_NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"alertmanager","image":"'$new_image'"}]}}}}'
                kubectl rollout status deployment/alertmanager -n $MONITORING_NAMESPACE
            fi
            ;;
        4)
            echo "Updating all components to latest versions..."
            kubectl patch deployment prometheus -n $MONITORING_NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"prometheus","image":"prom/prometheus:latest"}]}}}}'
            kubectl patch deployment grafana -n $MONITORING_NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"grafana","image":"grafana/grafana:latest"}]}}}}'
            kubectl patch deployment alertmanager -n $MONITORING_NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"alertmanager","image":"prom/alertmanager:latest"}]}}}}'
            
            kubectl rollout status deployment/prometheus -n $MONITORING_NAMESPACE
            kubectl rollout status deployment/grafana -n $MONITORING_NAMESPACE
            kubectl rollout status deployment/alertmanager -n $MONITORING_NAMESPACE
            ;;
        *)
            echo "Invalid option"
            return 1
            ;;
    esac
    
    echo "✓ Update completed"
}

# Function to show monitoring logs
show_monitoring_logs() {
    echo "Monitoring Logs"
    echo "==============="
    echo ""
    
    echo "Available components:"
    echo "1. Prometheus"
    echo "2. Grafana"
    echo "3. AlertManager"
    echo ""
    
    read -p "Select component (1-3): " choice
    
    case $choice in
        1)
            echo "Prometheus logs:"
            kubectl logs -l app=prometheus -n $MONITORING_NAMESPACE --tail=100 -f
            ;;
        2)
            echo "Grafana logs:"
            kubectl logs -l app=grafana -n $MONITORING_NAMESPACE --tail=100 -f
            ;;
        3)
            echo "AlertManager logs:"
            kubectl logs -l app=alertmanager -n $MONITORING_NAMESPACE --tail=100 -f
            ;;
        *)
            echo "Invalid option"
            return 1
            ;;
    esac
}

# Function to configure port forwarding
setup_port_forwarding() {
    echo "Setting up Port Forwarding"
    echo "=========================="
    echo ""
    
    echo "Available services:"
    echo "1. Prometheus (9090)"
    echo "2. Grafana (3000)"
    echo "3. AlertManager (9093)"
    echo "4. All services"
    echo ""
    
    read -p "Select service (1-4): " choice
    
    case $choice in
        1)
            echo "Starting port forwarding for Prometheus..."
            echo "Access at: http://localhost:9090"
            kubectl port-forward svc/prometheus 9090:9090 -n $MONITORING_NAMESPACE
            ;;
        2)
            echo "Starting port forwarding for Grafana..."
            echo "Access at: http://localhost:3000"
            kubectl port-forward svc/grafana 3000:3000 -n $MONITORING_NAMESPACE
            ;;
        3)
            echo "Starting port forwarding for AlertManager..."
            echo "Access at: http://localhost:9093"
            kubectl port-forward svc/alertmanager 9093:9093 -n $MONITORING_NAMESPACE
            ;;
        4)
            echo "Starting port forwarding for all services..."
            echo "This will run in background. Use 'pkill -f port-forward' to stop."
            echo ""
            echo "Access URLs:"
            echo "- Prometheus: http://localhost:9090"
            echo "- Grafana: http://localhost:3000"
            echo "- AlertManager: http://localhost:9093"
            
            kubectl port-forward svc/prometheus 9090:9090 -n $MONITORING_NAMESPACE &
            kubectl port-forward svc/grafana 3000:3000 -n $MONITORING_NAMESPACE &
            kubectl port-forward svc/alertmanager 9093:9093 -n $MONITORING_NAMESPACE &
            
            echo "Port forwarding started in background"
            ;;
        *)
            echo "Invalid option"
            return 1
            ;;
    esac
}

# Function to clean up monitoring stack
cleanup_monitoring() {
    echo "Cleaning up Monitoring Stack"
    echo "============================"
    echo ""
    
    echo "⚠️  WARNING: This will delete all monitoring components and data!"
    echo "This includes:"
    echo "- Prometheus deployment and data"
    echo "- Grafana deployment and dashboards"
    echo "- AlertManager deployment"
    echo "- All persistent volumes and data"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Cleanup cancelled"
        return 0
    fi
    
    echo "Deleting monitoring namespace and all resources..."
    kubectl delete namespace $MONITORING_NAMESPACE --ignore-not-found=true
    
    echo "Cleaning up persistent volumes..."
    kubectl get pv | grep "monitoring" | awk '{print $1}' | xargs -r kubectl delete pv
    
    echo "✓ Monitoring stack cleanup completed"
}

# Function to show menu
show_menu() {
    echo ""
    echo "Monitoring Management Menu"
    echo "=========================="
    echo "1. Show monitoring status"
    echo "2. Check monitoring health"
    echo "3. Restart monitoring components"
    echo "4. Backup monitoring configuration"
    echo "5. Update monitoring stack"
    echo "6. Show monitoring logs"
    echo "7. Setup port forwarding"
    echo "8. Cleanup monitoring stack"
    echo "9. Exit"
    echo ""
}

# Main execution
main() {
    echo "MinIO Monitoring Management"
    echo "=========================="
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        echo "Error: kubectl is not installed"
        exit 1
    fi
    
    # Interactive menu
    while true; do
        show_menu
        read -p "Select option (1-9): " choice
        
        case $choice in
            1) show_monitoring_status ;;
            2) check_monitoring_health ;;
            3) restart_monitoring ;;
            4) backup_monitoring_config ;;
            5) update_monitoring ;;
            6) show_monitoring_logs ;;
            7) setup_port_forwarding ;;
            8) cleanup_monitoring ;;
            9) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid option. Please select 1-9." ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Handle command line arguments
if [ $# -eq 1 ]; then
    case $1 in
        status) show_monitoring_status ;;
        health) check_monitoring_health ;;
        backup) backup_monitoring_config ;;
        cleanup) cleanup_monitoring ;;
        *) echo "Usage: $0 [status|health|backup|cleanup]"; exit 1 ;;
    esac
else
    main
fi
