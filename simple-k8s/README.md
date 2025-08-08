> ## 📋 완전한 MinIO 설치 가이드

### 🚀 사용 방법

#### 1. 완전 자동 설치 (권장)
bash
cd /home/luke/k8s
./install-minio-complete.sh


#### 2. 단계별 수동 설치
bash
# 1단계: 사전 검증
./00-pre-install-check.sh

# 2단계: 스케줄러 권한 설정
./01-setup-scheduler-permissions.sh

# 3단계: 스토리지 준비
./02-prepare-storage.sh

# 4단계: MinIO 애플리케이션 설치
./03-install-minio-app.sh

# 5단계: 설치 검증
./04-verify-installation.sh


#### 3. 완전 정리 (필요시)
bash
./cleanup-minio.sh


### 🔧 해결된 이전 오류들

1. ✅ 노드 호스트명 대소문자 불일치
   • 자동으로 실제 노드명 감지 및 사용

2. ✅ 스케줄러 권한 부족
   • PV/PVC 접근 권한 자동 설정

3. ✅ 기존 MinIO 데이터 충돌
   • 설치 전 자동 데이터 정리

4. ✅ 스토리지 용량 불일치
   • 적절한 용량으로 자동 설정

5. ✅ 디렉토리 권한 문제
   • 자동 권한 설정 (1000:1000)

### 📊 설치 후 접근 정보

• **MinIO Console**: http://<NODE-IP>:30901
• **MinIO API**: http://<NODE-IP>:30900
• **Username**: admin
• **Password**: password123

### 🛠️ 문제 해결

문제 발생 시:
bash
# 상태 확인
kubectl get pods -n minio
kubectl get pvc -n minio
kubectl get pv

# 로그 확인
kubectl logs -n minio <pod-name>

# 완전 재설치
./cleanup-minio.sh
./install-minio-complete.sh
