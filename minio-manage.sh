#!/bin/bash

echo "MinIO Management Commands:"
echo ""
echo "1. List buckets:"
echo "   kubectl exec -n minio minio-client -- mc ls myminio"
echo ""
echo "2. Create bucket:"
echo "   kubectl exec -n minio minio-client -- mc mb myminio/new-bucket"
echo ""
echo "3. Upload file:"
echo "   kubectl cp /path/to/file minio/minio-client:/tmp/file"
echo "   kubectl exec -n minio minio-client -- mc cp /tmp/file myminio/bucket-name/"
echo ""
echo "4. Download file:"
echo "   kubectl exec -n minio minio-client -- mc cp myminio/bucket-name/file /tmp/"
echo "   kubectl cp minio/minio-client:/tmp/file /path/to/local/file"
echo ""
echo "5. Check MinIO status:"
echo "   kubectl exec -n minio minio-client -- mc admin info myminio"
echo ""

# Interactive menu
while true; do
    echo ""
    echo "Choose an action:"
    echo "1) List buckets"
    echo "2) Create bucket"
    echo "3) MinIO admin info"
    echo "4) Open MinIO shell"
    echo "5) Exit"
    read -p "Enter choice [1-5]: " choice
    
    case $choice in
        1)
            echo "Listing buckets..."
            kubectl exec -n minio minio-client -- mc ls myminio
            ;;
        2)
            read -p "Enter bucket name: " bucket_name
            kubectl exec -n minio minio-client -- mc mb myminio/$bucket_name
            ;;
        3)
            echo "MinIO admin info..."
            kubectl exec -n minio minio-client -- mc admin info myminio
            ;;
        4)
            echo "Opening MinIO client shell..."
            kubectl exec -it -n minio minio-client -- /bin/sh
            ;;
        5)
            echo "Exiting..."
            break
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
done
