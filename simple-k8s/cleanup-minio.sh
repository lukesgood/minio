#!/bin/bash

echo "=== MinIO Complete Cleanup Script ==="
echo "This will remove ALL MinIO resources and data"
echo ""

read -p "Are you sure you want to proceed? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo "1. Deleting MinIO StatefulSet..."
kubectl delete statefulset minio -n minio --ignore-not-found=true

echo "2. Deleting MinIO PVCs..."
kubectl delete pvc -n minio --all --ignore-not-found=true

echo "3. Deleting MinIO Services..."
kubectl delete svc -n minio --all --ignore-not-found=true

echo "4. Deleting MinIO Secret..."
kubectl delete secret minio-secret -n minio --ignore-not-found=true

echo "5. Deleting MinIO namespace..."
kubectl delete namespace minio --ignore-not-found=true

echo "6. Deleting PersistentVolumes..."
kubectl delete pv minio-pv-1 minio-pv-2 minio-pv-3 --ignore-not-found=true

echo "7. Deleting StorageClass..."
kubectl delete storageclass local-storage --ignore-not-found=true

echo "8. Cleaning up local storage data..."
sudo rm -rf /media/luke/data1/.minio.sys /media/luke/data1/minio-data
sudo rm -rf /media/luke/data2/.minio.sys /media/luke/data2/minio-data  
sudo rm -rf /media/luke/data3/.minio.sys /media/luke/data3/minio-data

echo "9. Removing scheduler permissions (optional)..."
read -p "Remove scheduler permissions? (yes/no): " remove_perms
if [ "$remove_perms" = "yes" ]; then
    kubectl delete clusterrolebinding system:kube-scheduler-pv --ignore-not-found=true
    kubectl delete clusterrole system:kube-scheduler-pv --ignore-not-found=true
fi

echo "✅ MinIO cleanup completed!"
echo "You can now run the installation script again if needed."
