#!/bin/bash

# MinIO Maintenance and Monitoring Script
# This script provides various maintenance and monitoring operations for MinIO distributed cluster

set -e

MINIO_NAMESPACE="minio-system"
ALIAS_NAME="k8s-minio"

# Function to show cluster status
show_cluster_status() {
    echo "MinIO Cluster Status"
    echo "===================="
    echo ""
    
    echo "Kubernetes Pods:"
    kubectl get pods -n $MINIO_NAMESPACE -o wide
    echo ""
    
    echo "Kubernetes Services:"
    kubectl get svc -n $MINIO_NAMESPACE
    echo ""
    
    echo "Persistent Volumes:"
    kubectl get pv | grep minio
    echo ""
    
    echo "Persistent Volume Claims:"
    kubectl get pvc -n $MINIO_NAMESPACE
    echo ""
    
    if command -v mc &> /dev/null && mc alias list | grep -q $ALIAS_NAME; then
        echo "MinIO Server Info:"
        mc admin info $ALIAS_NAME
    else
        echo "MinIO client not configured. Run setup-minio-client.sh first."
    fi
}

# Function to check cluster health
check_cluster_health() {
    echo "Checking MinIO Cluster Health"
    echo "============================="
    echo ""
    
    # Check pod status
    echo "Pod Health Check:"
    TOTAL_PODS=$(kubectl get pods -n $MINIO_NAMESPACE -l app=minio --no-headers | wc -l)
    READY_PODS=$(kubectl get pods -n $MINIO_NAMESPACE -l app=minio --no-headers | grep Running | wc -l)
    
    echo "Total Pods: $TOTAL_PODS"
    echo "Ready Pods: $READY_PODS"
    
    if [ $READY_PODS -eq $TOTAL_PODS ]; then
        echo "✓ All pods are running"
    else
        echo "✗ Some pods are not running"
        kubectl get pods -n $MINIO_NAMESPACE -l app=minio | grep -v Running || true
    fi
    echo ""
    
    # Check PVC status
    echo "Storage Health Check:"
    TOTAL_PVC=$(kubectl get pvc -n $MINIO_NAMESPACE --no-headers | wc -l)
    BOUND_PVC=$(kubectl get pvc -n $MINIO_NAMESPACE --no-headers | grep Bound | wc -l)
    
    echo "Total PVCs: $TOTAL_PVC"
    echo "Bound PVCs: $BOUND_PVC"
    
    if [ $BOUND_PVC -eq $TOTAL_PVC ]; then
        echo "✓ All storage volumes are bound"
    else
        echo "✗ Some storage volumes are not bound"
        kubectl get pvc -n $MINIO_NAMESPACE | grep -v Bound || true
    fi
    echo ""
    
    # MinIO specific health check
    if command -v mc &> /dev/null && mc alias list | grep -q $ALIAS_NAME; then
        echo "MinIO Service Health Check:"
        if mc admin info $ALIAS_NAME > /dev/null 2>&1; then
            echo "✓ MinIO service is responding"
            
            # Check if healing is needed
            echo "Checking for healing requirements..."
            HEAL_STATUS=$(mc admin heal $ALIAS_NAME --dry-run --json 2>/dev/null | jq -r '.HealInfo.Status' 2>/dev/null || echo "unknown")
            if [ "$HEAL_STATUS" = "success" ]; then
                echo "✓ No healing required"
            else
                echo "⚠ Healing may be required - run healing check"
            fi
        else
            echo "✗ MinIO service is not responding"
        fi
    fi
}

# Function to scale MinIO cluster
scale_cluster() {
    echo "MinIO Cluster Scaling"
    echo "===================="
    echo ""
    
    CURRENT_REPLICAS=$(kubectl get statefulset minio -n $MINIO_NAMESPACE -o jsonpath='{.spec.replicas}')
    echo "Current replicas: $CURRENT_REPLICAS"
    echo ""
    
    read -p "Enter new replica count: " NEW_REPLICAS
    
    if ! [[ "$NEW_REPLICAS" =~ ^[0-9]+$ ]] || [ "$NEW_REPLICAS" -lt 4 ]; then
        echo "Error: Replica count must be a number >= 4 for MinIO distributed mode"
        return 1
    fi
    
    if [ "$NEW_REPLICAS" -eq "$CURRENT_REPLICAS" ]; then
        echo "No change needed. Current replicas already set to $NEW_REPLICAS"
        return 0
    fi
    
    echo "Scaling MinIO from $CURRENT_REPLICAS to $NEW_REPLICAS replicas..."
    
    # Update StatefulSet
    kubectl patch statefulset minio -n $MINIO_NAMESPACE -p '{"spec":{"replicas":'$NEW_REPLICAS'}}'
    
    echo "Waiting for scaling to complete..."
    kubectl rollout status statefulset/minio -n $MINIO_NAMESPACE --timeout=600s
    
    echo "✓ Scaling completed successfully"
}

# Function to backup MinIO configuration
backup_config() {
    echo "Backing up MinIO Configuration"
    echo "=============================="
    echo ""
    
    BACKUP_DIR="/tmp/minio-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p $BACKUP_DIR
    
    echo "Creating backup in: $BACKUP_DIR"
    
    # Backup Kubernetes resources
    kubectl get all -n $MINIO_NAMESPACE -o yaml > $BACKUP_DIR/minio-resources.yaml
    kubectl get pv -o yaml | grep -A 1000 "name: minio-pv" > $BACKUP_DIR/minio-pvs.yaml
    kubectl get secret minio-credentials -n $MINIO_NAMESPACE -o yaml > $BACKUP_DIR/minio-secret.yaml
    kubectl get storageclass local-storage -o yaml > $BACKUP_DIR/storage-class.yaml
    
    # Backup MinIO configuration if mc is available
    if command -v mc &> /dev/null && mc alias list | grep -q $ALIAS_NAME; then
        echo "Backing up MinIO server configuration..."
        mc admin config export $ALIAS_NAME > $BACKUP_DIR/minio-server-config.json 2>/dev/null || echo "Could not export server config"
        mc admin policy list $ALIAS_NAME > $BACKUP_DIR/minio-policies.txt 2>/dev/null || echo "Could not export policies"
        mc admin user list $ALIAS_NAME > $BACKUP_DIR/minio-users.txt 2>/dev/null || echo "Could not export users"
    fi
    
    echo "✓ Backup completed: $BACKUP_DIR"
    echo "Files created:"
    ls -la $BACKUP_DIR
}

# Function to perform cluster healing
heal_cluster() {
    echo "MinIO Cluster Healing"
    echo "===================="
    echo ""
    
    if ! command -v mc &> /dev/null || ! mc alias list | grep -q $ALIAS_NAME; then
        echo "Error: MinIO client not configured. Run setup-minio-client.sh first."
        return 1
    fi
    
    echo "Checking healing status..."
    mc admin heal $ALIAS_NAME --dry-run
    echo ""
    
    read -p "Do you want to start healing? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Starting cluster healing..."
        mc admin heal $ALIAS_NAME
        echo "✓ Healing completed"
    else
        echo "Healing cancelled"
    fi
}

# Function to update MinIO
update_minio() {
    echo "MinIO Update"
    echo "============"
    echo ""
    
    CURRENT_IMAGE=$(kubectl get statefulset minio -n $MINIO_NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
    echo "Current image: $CURRENT_IMAGE"
    echo ""
    
    read -p "Enter new MinIO image (e.g., minio/minio:RELEASE.2024-01-01T00-00-00Z): " NEW_IMAGE
    
    if [ -z "$NEW_IMAGE" ]; then
        echo "No image specified. Using latest..."
        NEW_IMAGE="minio/minio:latest"
    fi
    
    echo "Updating MinIO image to: $NEW_IMAGE"
    
    # Update the StatefulSet
    kubectl patch statefulset minio -n $MINIO_NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"minio","image":"'$NEW_IMAGE'"}]}}}}'
    
    echo "Waiting for rolling update to complete..."
    kubectl rollout status statefulset/minio -n $MINIO_NAMESPACE --timeout=600s
    
    echo "✓ Update completed successfully"
}

# Function to clean up failed pods
cleanup_failed_pods() {
    echo "Cleaning up failed pods..."
    
    FAILED_PODS=$(kubectl get pods -n $MINIO_NAMESPACE -l app=minio --field-selector=status.phase=Failed -o name)
    
    if [ -z "$FAILED_PODS" ]; then
        echo "No failed pods found"
        return 0
    fi
    
    echo "Found failed pods:"
    echo "$FAILED_PODS"
    echo ""
    
    read -p "Delete failed pods? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$FAILED_PODS" | xargs kubectl delete -n $MINIO_NAMESPACE
        echo "✓ Failed pods cleaned up"
    else
        echo "Cleanup cancelled"
    fi
}

# Function to show logs
show_logs() {
    echo "MinIO Logs"
    echo "=========="
    echo ""
    
    echo "Available pods:"
    kubectl get pods -n $MINIO_NAMESPACE -l app=minio
    echo ""
    
    read -p "Enter pod name (or 'all' for all pods): " POD_NAME
    
    if [ "$POD_NAME" = "all" ]; then
        echo "Showing logs from all MinIO pods..."
        kubectl logs -n $MINIO_NAMESPACE -l app=minio --tail=50
    else
        echo "Showing logs from pod: $POD_NAME"
        kubectl logs -n $MINIO_NAMESPACE $POD_NAME --tail=100 -f
    fi
}

# Function to show menu
show_menu() {
    echo ""
    echo "MinIO Maintenance Menu"
    echo "======================"
    echo "1. Show cluster status"
    echo "2. Check cluster health"
    echo "3. Scale cluster"
    echo "4. Backup configuration"
    echo "5. Heal cluster"
    echo "6. Update MinIO"
    echo "7. Cleanup failed pods"
    echo "8. Show logs"
    echo "9. Exit"
    echo ""
}

# Main execution
main() {
    echo "MinIO Distributed Cluster Maintenance"
    echo "====================================="
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        echo "Error: kubectl is not installed"
        exit 1
    fi
    
    if ! kubectl get namespace $MINIO_NAMESPACE &> /dev/null; then
        echo "Error: MinIO namespace not found"
        exit 1
    fi
    
    # Interactive menu
    while true; do
        show_menu
        read -p "Select option (1-9): " choice
        
        case $choice in
            1) show_cluster_status ;;
            2) check_cluster_health ;;
            3) scale_cluster ;;
            4) backup_config ;;
            5) heal_cluster ;;
            6) update_minio ;;
            7) cleanup_failed_pods ;;
            8) show_logs ;;
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
        status) show_cluster_status ;;
        health) check_cluster_health ;;
        backup) backup_config ;;
        heal) heal_cluster ;;
        cleanup) cleanup_failed_pods ;;
        *) echo "Usage: $0 [status|health|backup|heal|cleanup]"; exit 1 ;;
    esac
else
    main
fi
