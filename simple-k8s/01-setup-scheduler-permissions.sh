#!/bin/bash

echo "=== Setting up Scheduler Permissions ==="

# 스케줄러 권한 확인
echo "1. Checking current scheduler permissions..."
if kubectl auth can-i list persistentvolumes --as=system:kube-scheduler > /dev/null 2>&1; then
    echo "✅ Scheduler already has required permissions"
    exit 0
fi

echo "2. Creating scheduler permissions..."

# 스케줄러 권한 YAML 생성
cat > /tmp/scheduler-permissions.yaml << 'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:kube-scheduler-pv
rules:
- apiGroups: [""]
  resources: ["persistentvolumes", "persistentvolumeclaims"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses", "csidrivers"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["statefulsets", "replicasets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["services", "replicationcontrollers", "configmaps"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-scheduler-pv
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-scheduler-pv
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: system:kube-scheduler
EOF

# 권한 적용
kubectl apply -f /tmp/scheduler-permissions.yaml

if [ $? -eq 0 ]; then
    echo "✅ Scheduler permissions created successfully"
    
    # 스케줄러 재시작
    echo "3. Restarting scheduler to apply new permissions..."
    kubectl delete pod -n kube-system -l component=kube-scheduler
    
    # 스케줄러가 다시 시작될 때까지 대기
    echo "4. Waiting for scheduler to restart..."
    sleep 10
    kubectl wait --for=condition=ready pod -l component=kube-scheduler -n kube-system --timeout=60s
    
    # 권한 재확인
    echo "5. Verifying new permissions..."
    sleep 5
    if kubectl auth can-i list persistentvolumes --as=system:kube-scheduler > /dev/null 2>&1; then
        echo "✅ Scheduler permissions verified successfully"
    else
        echo "⚠️  Permissions may take a moment to propagate"
    fi
else
    echo "❌ Failed to create scheduler permissions"
    exit 1
fi

# 임시 파일 정리
rm -f /tmp/scheduler-permissions.yaml

echo "✅ Scheduler permissions setup complete"
