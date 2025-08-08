#!/bin/bash

echo "=== Installing MinIO Application ==="

echo "1. Creating MinIO namespace..."
kubectl create namespace minio --dry-run=client -o yaml | kubectl apply -f -

echo "2. Creating MinIO credentials secret..."
# 기본 자격증명 (필요시 수정 가능)
MINIO_USER="admin"
MINIO_PASSWORD="password123"

kubectl create secret generic minio-secret \
  --from-literal=MINIO_ROOT_USER="$MINIO_USER" \
  --from-literal=MINIO_ROOT_PASSWORD="$MINIO_PASSWORD" \
  --namespace=minio \
  --dry-run=client -o yaml | kubectl apply -f -

echo "3. Creating MinIO services..."
cat > /tmp/minio-services.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: minio-headless
  namespace: minio
spec:
  clusterIP: None
  selector:
    app: minio
  ports:
  - port: 9000
    name: api
  - port: 9001
    name: console
---
apiVersion: v1
kind: Service
metadata:
  name: minio-api
  namespace: minio
spec:
  type: NodePort
  selector:
    app: minio
  ports:
  - port: 9000
    targetPort: 9000
    nodePort: 30900
    name: api
---
apiVersion: v1
kind: Service
metadata:
  name: minio-console
  namespace: minio
spec:
  type: NodePort
  selector:
    app: minio
  ports:
  - port: 9001
    targetPort: 9001
    nodePort: 30901
    name: console
EOF

kubectl apply -f /tmp/minio-services.yaml

echo "4. Creating MinIO StatefulSet..."
cat > /tmp/minio-statefulset.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: minio
  namespace: minio
spec:
  serviceName: minio-headless
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        args:
        - server
        - /data
        - --console-address
        - ":9001"
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: MINIO_ROOT_USER
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: MINIO_ROOT_PASSWORD
        ports:
        - containerPort: 9000
          name: api
        - containerPort: 9001
          name: console
        volumeMounts:
        - name: data
          mountPath: /data
        livenessProbe:
          httpGet:
            path: /minio/health/live
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /minio/health/ready
            port: 9000
          initialDelaySeconds: 10
          periodSeconds: 10
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: local-storage
      resources:
        requests:
          storage: 8Gi
EOF

kubectl apply -f /tmp/minio-statefulset.yaml

echo "5. Waiting for MinIO to be ready..."
kubectl wait --for=condition=ready pod -l app=minio -n minio --timeout=300s

if [ $? -eq 0 ]; then
    echo "✅ MinIO is ready!"
else
    echo "⚠️  MinIO is taking longer than expected. Checking status..."
    kubectl get pods -n minio
    kubectl describe pod -l app=minio -n minio | tail -10
fi

# 임시 파일 정리
rm -f /tmp/minio-services.yaml /tmp/minio-statefulset.yaml

echo "✅ MinIO application installation complete"
