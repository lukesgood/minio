# MinIO 배포 - 문제 해결 및 관리

## 🔧 문제 해결 가이드

### 일반적인 문제 및 해결책

#### 문제 1: 파드가 Pending 상태에서 멈춤
**증상:**
```bash
kubectl get pods -n minio-system
NAME      READY   STATUS    RESTARTS   AGE
minio-0   1/1     Running   0          2m
minio-1   0/1     Pending   0          2m
```

**진단:**
```bash
kubectl describe pod minio-1 -n minio-system
```

**일반적인 원인 및 해결책:**

1. **사용 가능한 영구 볼륨 없음**
   ```
   Events:
   Warning  FailedScheduling  1m  default-scheduler  0/2 nodes are available: 
   1 node(s) didn't find available persistent volumes to bind
   ```
   
   **해결책:**
   ```bash
   # PV 상태 확인
   kubectl get pv | grep minio
   
   # PV가 없으면 수동으로 생성
   kubectl apply -f - <<EOF
   apiVersion: v1
   kind: PersistentVolume
   metadata:
     name: minio-pv-1
   spec:
     capacity:
       storage: 10Gi
     accessModes:
       - ReadWriteOnce
     local:
       path: /mnt/minio-data
     nodeAffinity:
       required:
         nodeSelectorTerms:
         - matchExpressions:
           - key: kubernetes.io/hostname
             operator: In
             values:
             - your-node-name
   EOF
   ```

2. **스케줄링을 방해하는 노드 Taint**
   ```
   Events:
   Warning  FailedScheduling  1m  default-scheduler  0/2 nodes are available: 
   1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }
   ```
   
   **해결책:**
   ```bash
   # 옵션 1: control-plane에서 taint 제거 (프로덕션에서는 권장하지 않음)
   kubectl taint nodes --all node-role.kubernetes.io/control-plane-
   
   # 옵션 2: MinIO 파드에 toleration 추가 (StatefulSet 수정)
   spec:
     template:
       spec:
         tolerations:
         - key: node-role.kubernetes.io/control-plane
           operator: Exists
           effect: NoSchedule
   ```

3. **리소스 부족**
   ```
   Events:
   Warning  FailedScheduling  1m  default-scheduler  0/2 nodes are available: 
   2 Insufficient memory, 2 Insufficient cpu
   ```
   
   **해결책:**
   ```bash
   # 리소스 요구사항 줄이기
   kubectl patch statefulset minio -n minio-system -p='
   {
     "spec": {
       "template": {
         "spec": {
           "containers": [{
             "name": "minio",
             "resources": {
               "requests": {
                 "memory": "256Mi",
                 "cpu": "100m"
               },
               "limits": {
                 "memory": "512Mi",
                 "cpu": "250m"
               }
             }
           }]
         }
       }
     }
   }'
   ```

#### 문제 2: 파드 CrashLoopBackOff
**증상:**
```bash
NAME      READY   STATUS             RESTARTS   AGE
minio-0   0/1     CrashLoopBackOff   3          2m
```

**진단:**
```bash
# 파드 로그 확인
kubectl logs minio-0 -n minio-system

# 파드가 재시작된 경우 이전 컨테이너 로그 확인
kubectl logs minio-0 -n minio-system --previous
```

**일반적인 원인 및 해결책:**

1. **권한 문제**
   ```
   Error: Unable to write to the backend
   ```
   
   **해결책:**
   ```bash
   # 스토리지 디렉토리 권한 확인
   kubectl exec -it minio-0 -n minio-system -- ls -la /data
   
   # 권한 거부 시 노드에서 수정
   sudo chown -R 1000:1000 /mnt/minio-data
   sudo chmod -R 755 /mnt/minio-data
   ```

2. **디스크 공간 부족**
   ```
   Error: Drive '/data' has insufficient space
   ```
   
   **해결책:**
   ```bash
   # 노드의 디스크 공간 확인
   kubectl get nodes -o wide
   
   # 노드에 SSH 접속하여 확인
   df -h /mnt/minio-data
   
   # 공간 정리 또는 스토리지 크기 증가
   ```

3. **네트워크 연결 문제**
   ```
   Error: Unable to connect to http://minio-1.minio-headless.minio-system.svc.cluster.local:9000
   ```
   
   **해결책:**
   ```bash
   # 서비스 엔드포인트 확인
   kubectl get endpoints minio-headless -n minio-system
   
   # DNS 해결 테스트
   kubectl run test-pod --rm -i --tty --image=busybox -- nslookup minio-headless.minio-system.svc.cluster.local
   
   # 네트워크 정책 확인
   kubectl get networkpolicies -n minio-system
   ```

#### 문제 3: MinIO 콘솔에 접근할 수 없음
**증상:**
- 브라우저에서 "연결 거부" 또는 타임아웃 표시
- 클러스터 외부에서 콘솔 URL에 접근할 수 없음

**진단:**
```bash
# 서비스 상태 확인
kubectl get svc -n minio-system

# NodePort가 접근 가능한지 확인
kubectl get svc minio-console -n minio-system -o yaml

# 클러스터 내부에서 테스트
kubectl run test-pod --rm -i --tty --image=curlimages/curl -- curl http://minio-console:9001
```

**해결책:**

1. **NodePort 서비스 문제**
   ```bash
   # NodePort 서비스 존재 확인
   kubectl get svc minio-console -n minio-system
   
   # 없으면 생성
   kubectl expose statefulset minio --type=NodePort --port=9001 --target-port=9001 --name=minio-console -n minio-system
   
   # 특정 NodePort 설정
   kubectl patch svc minio-console -n minio-system -p '{"spec":{"ports":[{"port":9001,"nodePort":30901,"targetPort":9001}]}}'
   ```

2. **방화벽 문제**
   ```bash
   # 노드에서 포트가 열려있는지 확인
   sudo ufw status
   sudo ufw allow 30901
   
   # 클라우드 제공업체의 경우 보안 그룹 확인
   # AWS: 포트 30901에 대한 인바운드 트래픽 허용
   # GCP: 포트 30901에 대한 방화벽 규칙 생성
   ```

3. **로드 밸런서 문제 (클라우드 사용 시)**
   ```bash
   # 서비스 유형을 LoadBalancer로 변경
   kubectl patch svc minio-console -n minio-system -p '{"spec":{"type":"LoadBalancer"}}'
   
   # 외부 IP 대기
   kubectl get svc minio-console -n minio-system -w
   ```

### 진단 명령어

#### 파드 수준 진단
```bash
# 자세한 파드 정보 가져오기
kubectl describe pod minio-0 -n minio-system

# 파드 로그 확인 (현재)
kubectl logs minio-0 -n minio-system

# 파드 로그 확인 (이전 컨테이너)
kubectl logs minio-0 -n minio-system --previous

# 파드에서 명령 실행
kubectl exec -it minio-0 -n minio-system -- /bin/bash

# 파드 리소스 사용량 확인
kubectl top pod minio-0 -n minio-system
```

#### 스토리지 진단
```bash
# PVC 상태 확인
kubectl get pvc -n minio-system

# PV 상태 확인
kubectl get pv | grep minio

# 바인딩 문제에 대한 PVC 설명
kubectl describe pvc data-minio-0 -n minio-system

# 스토리지 클래스 확인
kubectl get storageclass minio-local-storage -o yaml
```

#### 네트워크 진단
```bash
# 서비스 및 엔드포인트 확인
kubectl get svc,endpoints -n minio-system

# 내부 연결 테스트
kubectl run test-pod --rm -i --tty --image=busybox -- wget -qO- http://minio-api:9000/minio/health/live

# DNS 해결 확인
kubectl run test-pod --rm -i --tty --image=busybox -- nslookup minio-headless.minio-system.svc.cluster.local

# 테스트를 위한 포트 포워딩
kubectl port-forward svc/minio-console 9001:9001 -n minio-system
```

#### 클러스터 수준 진단
```bash
# 노드 상태 및 리소스 확인
kubectl get nodes -o wide
kubectl describe nodes

# 클러스터 이벤트 확인
kubectl get events --sort-by='.lastTimestamp' -n minio-system

# 리소스 할당량 확인
kubectl describe quota -n minio-system

# RBAC 권한 확인
kubectl auth can-i create pods --namespace=minio-system
```

## 📊 관리 및 운영

### 확장 작업

#### 수평 확장 (더 많은 복제본 추가)
```bash
# MinIO StatefulSet 확장
kubectl scale statefulset minio --replicas=4 -n minio-system

# 새 복제본을 위한 추가 PV 생성
for i in {2..3}; do
  kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-pv-$i
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  local:
    path: /mnt/minio-data
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - node-$i
EOF
done

# 확장 진행 상황 모니터링
kubectl get pods -n minio-system -w
```

#### 수직 확장 (리소스 증가)
```bash
# 리소스 제한 업데이트
kubectl patch statefulset minio -n minio-system -p='
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "minio",
          "resources": {
            "requests": {
              "memory": "1Gi",
              "cpu": "500m"
            },
            "limits": {
              "memory": "2Gi",
              "cpu": "1000m"
            }
          }
        }]
      }
    }
  }
}'

# 변경사항 적용을 위한 롤링 재시작
kubectl rollout restart statefulset/minio -n minio-system
```

### 백업 및 복구

#### 데이터 백업
```bash
# 백업 작업 생성
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: minio-backup
  namespace: minio-system
spec:
  template:
    spec:
      containers:
      - name: mc
        image: quay.io/minio/mc:latest
        command:
        - /bin/sh
        - -c
        - |
          mc alias set source http://minio-api:9000 \$MINIO_ROOT_USER \$MINIO_ROOT_PASSWORD
          mc alias set backup s3://your-backup-bucket
          mc mirror source backup --overwrite
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: accesskey
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: secretkey
      restartPolicy: OnFailure
EOF
```

#### 구성 백업
```bash
# Kubernetes 리소스 백업
kubectl get all,pv,pvc,secrets,configmaps -n minio-system -o yaml > minio-backup.yaml

# 특정 리소스 백업
kubectl get statefulset minio -n minio-system -o yaml > minio-statefulset.yaml
kubectl get svc -n minio-system -o yaml > minio-services.yaml
```

### 모니터링 및 알림

#### 기본 모니터링
```bash
# 파드 상태 확인
kubectl get pods -n minio-system -o wide

# 리소스 사용량 확인
kubectl top pods -n minio-system

# 스토리지 사용량 확인
kubectl exec -it minio-0 -n minio-system -- df -h /data

# MinIO 서버 상태 확인
kubectl exec -it minio-0 -n minio-system -- mc admin info local
```

#### 고급 모니터링 설정
```yaml
# Prometheus용 ServiceMonitor
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: minio
  namespace: minio-system
spec:
  selector:
    matchLabels:
      app: minio
  endpoints:
  - port: api
    path: /minio/v2/metrics/cluster
```

### 보안 관리

#### 자격 증명 업데이트
```bash
# 새 시크릿 생성
kubectl create secret generic minio-credentials-new \
    --from-literal=accesskey="newadmin" \
    --from-literal=secretkey="newpassword123" \
    --namespace="minio-system"

# 새 시크릿을 사용하도록 StatefulSet 업데이트
kubectl patch statefulset minio -n minio-system -p='
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "minio",
          "env": [
            {
              "name": "MINIO_ROOT_USER",
              "valueFrom": {
                "secretKeyRef": {
                  "name": "minio-credentials-new",
                  "key": "accesskey"
                }
              }
            },
            {
              "name": "MINIO_ROOT_PASSWORD",
              "valueFrom": {
                "secretKeyRef": {
                  "name": "minio-credentials-new",
                  "key": "secretkey"
                }
              }
            }
          ]
        }]
      }
    }
  }
}'

# 롤링 재시작
kubectl rollout restart statefulset/minio -n minio-system
```

#### TLS 구성
```bash
# TLS 시크릿 생성
kubectl create secret tls minio-tls \
    --cert=path/to/tls.crt \
    --key=path/to/tls.key \
    -n minio-system

# TLS를 사용하도록 StatefulSet 업데이트
kubectl patch statefulset minio -n minio-system -p='
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "minio",
          "env": [
            {
              "name": "MINIO_SERVER_URL",
              "value": "https://minio-api:9000"
            }
          ],
          "volumeMounts": [
            {
              "name": "tls-certs",
              "mountPath": "/root/.minio/certs"
            }
          ]
        }],
        "volumes": [
          {
            "name": "tls-certs",
            "secret": {
              "secretName": "minio-tls"
            }
          }
        ]
      }
    }
  }
}'
```

---

*이것으로 포괄적인 MinIO 배포 문서가 완성됩니다.*
