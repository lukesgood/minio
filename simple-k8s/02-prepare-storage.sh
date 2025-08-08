#!/bin/bash

echo "=== Preparing Storage for MinIO ==="

# 실제 노드 호스트명 가져오기
ACTUAL_HOSTNAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "Detected node hostname: $ACTUAL_HOSTNAME"

# 스토리지 디렉토리 배열
STORAGE_DIRS=("/media/luke/data1" "/media/luke/data2" "/media/luke/data3")

echo "1. Cleaning up existing MinIO data..."
for dir in "${STORAGE_DIRS[@]}"; do
    if [ -d "$dir/.minio.sys" ]; then
        echo "   Removing existing MinIO data from $dir"
        sudo rm -rf "$dir/.minio.sys" "$dir/minio-data"
    fi
done

echo "2. Setting up directory permissions..."
for dir in "${STORAGE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "   Setting permissions for $dir"
        sudo chown -R 1000:1000 "$dir"
        sudo chmod -R 755 "$dir"
    else
        echo "   Creating directory $dir"
        sudo mkdir -p "$dir"
        sudo chown -R 1000:1000 "$dir"
        sudo chmod -R 755 "$dir"
    fi
done

echo "3. Creating StorageClass..."
cat > /tmp/minio-storageclass.yaml << 'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
EOF

kubectl apply -f /tmp/minio-storageclass.yaml

echo "4. Creating PersistentVolumes with correct hostname..."
cat > /tmp/minio-pv.yaml << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-1
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /media/luke/data1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $ACTUAL_HOSTNAME
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-2
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /media/luke/data2
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $ACTUAL_HOSTNAME
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-3
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /media/luke/data3
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $ACTUAL_HOSTNAME
EOF

kubectl apply -f /tmp/minio-pv.yaml

echo "5. Verifying PV creation..."
kubectl get pv | grep minio-pv

# 임시 파일 정리
rm -f /tmp/minio-storageclass.yaml /tmp/minio-pv.yaml

echo "✅ Storage preparation complete"
