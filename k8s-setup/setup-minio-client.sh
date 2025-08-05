#!/bin/bash

# MinIO Client (mc) Setup Script
# This script installs and configures the MinIO client to work with the distributed cluster

set -e

echo "Setting up MinIO Client (mc)..."

# Configuration
MINIO_NAMESPACE="minio-system"
ALIAS_NAME="k8s-minio"

# Function to install MinIO client
install_minio_client() {
    echo "Installing MinIO client..."
    
    # Check if mc is already installed
    if command -v mc &> /dev/null; then
        echo "MinIO client is already installed"
        mc --version
        return
    fi
    
    # Download and install mc
    echo "Downloading MinIO client..."
    curl -O https://dl.min.io/client/mc/release/linux-amd64/mc
    chmod +x mc
    sudo mv mc /usr/local/bin/
    
    echo "MinIO client installed successfully"
    mc --version
}

# Function to configure MinIO client
configure_minio_client() {
    echo "Configuring MinIO client..."
    
    # Get MinIO credentials from Kubernetes secret
    ACCESS_KEY=$(kubectl get secret minio-credentials -n $MINIO_NAMESPACE -o jsonpath='{.data.accesskey}' | base64 -d)
    SECRET_KEY=$(kubectl get secret minio-credentials -n $MINIO_NAMESPACE -o jsonpath='{.data.secretkey}' | base64 -d)
    
    # Get node IP for MinIO API
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
    if [ -z "$NODE_IP" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    fi
    
    MINIO_URL="http://$NODE_IP:30900"
    
    echo "Configuring alias '$ALIAS_NAME' for MinIO at $MINIO_URL"
    
    # Configure mc alias
    mc alias set $ALIAS_NAME $MINIO_URL $ACCESS_KEY $SECRET_KEY
    
    echo "MinIO client configured successfully!"
}

# Function to test MinIO connection
test_minio_connection() {
    echo "Testing MinIO connection..."
    
    # Test connection
    if mc admin info $ALIAS_NAME; then
        echo "✓ Connection to MinIO cluster successful!"
    else
        echo "✗ Failed to connect to MinIO cluster"
        return 1
    fi
    
    # Show cluster status
    echo ""
    echo "MinIO Cluster Information:"
    echo "=========================="
    mc admin info $ALIAS_NAME
}

# Function to create sample bucket and test operations
test_operations() {
    echo ""
    echo "Testing MinIO operations..."
    
    # Create a test bucket
    BUCKET_NAME="test-bucket"
    echo "Creating test bucket: $BUCKET_NAME"
    mc mb $ALIAS_NAME/$BUCKET_NAME 2>/dev/null || echo "Bucket already exists"
    
    # List buckets
    echo "Listing buckets:"
    mc ls $ALIAS_NAME
    
    # Create a test file and upload
    echo "Testing file upload..."
    echo "Hello from MinIO distributed cluster!" > /tmp/test-file.txt
    mc cp /tmp/test-file.txt $ALIAS_NAME/$BUCKET_NAME/
    
    # List objects in bucket
    echo "Listing objects in $BUCKET_NAME:"
    mc ls $ALIAS_NAME/$BUCKET_NAME
    
    # Download and verify file
    echo "Testing file download..."
    mc cp $ALIAS_NAME/$BUCKET_NAME/test-file.txt /tmp/downloaded-file.txt
    
    if diff /tmp/test-file.txt /tmp/downloaded-file.txt > /dev/null; then
        echo "✓ File upload/download test successful!"
    else
        echo "✗ File upload/download test failed!"
    fi
    
    # Cleanup test files
    rm -f /tmp/test-file.txt /tmp/downloaded-file.txt
    
    echo ""
    echo "Basic operations test completed!"
}

# Function to display usage examples
show_usage_examples() {
    echo ""
    echo "=========================================="
    echo "MinIO Client Usage Examples"
    echo "=========================================="
    echo ""
    echo "Basic Commands:"
    echo "==============="
    echo "# List buckets"
    echo "mc ls $ALIAS_NAME"
    echo ""
    echo "# Create bucket"
    echo "mc mb $ALIAS_NAME/my-bucket"
    echo ""
    echo "# Upload file"
    echo "mc cp /path/to/file $ALIAS_NAME/my-bucket/"
    echo ""
    echo "# Download file"
    echo "mc cp $ALIAS_NAME/my-bucket/file /local/path/"
    echo ""
    echo "# Sync directory"
    echo "mc mirror /local/directory $ALIAS_NAME/my-bucket/"
    echo ""
    echo "# Remove object"
    echo "mc rm $ALIAS_NAME/my-bucket/file"
    echo ""
    echo "# Remove bucket (must be empty)"
    echo "mc rb $ALIAS_NAME/my-bucket"
    echo ""
    echo "Administrative Commands:"
    echo "========================"
    echo "# Cluster info"
    echo "mc admin info $ALIAS_NAME"
    echo ""
    echo "# Server info"
    echo "mc admin info $ALIAS_NAME --json"
    echo ""
    echo "# Heal cluster (if needed)"
    echo "mc admin heal $ALIAS_NAME"
    echo ""
    echo "# Service restart"
    echo "mc admin service restart $ALIAS_NAME"
    echo ""
    echo "Policy Management:"
    echo "=================="
    echo "# List policies"
    echo "mc admin policy list $ALIAS_NAME"
    echo ""
    echo "# Create user"
    echo "mc admin user add $ALIAS_NAME newuser newpassword"
    echo ""
    echo "# Set policy for user"
    echo "mc admin policy set $ALIAS_NAME readwrite user=newuser"
    echo ""
}

# Main execution
main() {
    echo "MinIO Client Setup"
    echo "=================="
    echo ""
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        echo "Error: kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if MinIO is deployed
    if ! kubectl get namespace $MINIO_NAMESPACE &> /dev/null; then
        echo "Error: MinIO namespace '$MINIO_NAMESPACE' not found"
        echo "Please deploy MinIO first using deploy-minio-distributed.sh"
        exit 1
    fi
    
    # Check if MinIO pods are running
    if ! kubectl get pods -n $MINIO_NAMESPACE -l app=minio | grep -q Running; then
        echo "Error: MinIO pods are not running"
        echo "Please ensure MinIO is properly deployed and running"
        exit 1
    fi
    
    echo "MinIO deployment found. Proceeding with client setup..."
    echo ""
    
    # Execute setup steps
    install_minio_client
    configure_minio_client
    test_minio_connection
    test_operations
    show_usage_examples
    
    echo ""
    echo "MinIO client setup completed successfully!"
    echo "You can now use 'mc' command with alias '$ALIAS_NAME' to interact with your MinIO cluster."
}

# Run main function
main "$@"
