# Kubernetes에서 MinIO 분산 배포 - 완전한 문서

## 📚 문서 개요

이 저장소는 Kubernetes 클러스터에서 MinIO를 분산 모드로 배포하기 위한 포괄적인 문서와 스크립트를 포함합니다. 문서는 여러 개의 집중된 가이드로 구성되어 있습니다:

### 📖 문서 구조

| 문서 | 목적 | 대상 사용자 |
|----------|---------|-----------------|
| **[MINIO_DEPLOYMENT_GUIDE_KR.md](./MINIO_DEPLOYMENT_GUIDE_KR.md)** | 개요, 아키텍처, 빠른 시작 | 모든 사용자 |
| **[MINIO_DEPLOYMENT_STEPS_KR.md](./MINIO_DEPLOYMENT_STEPS_KR.md)** | 자세한 단계별 과정 | 운영자, DevOps |
| **[MINIO_TROUBLESHOOTING_KR.md](./MINIO_TROUBLESHOOTING_KR.md)** | 일반적인 문제 및 관리 | 지원, 운영 |
| **[MINIO_SECURITY_GUIDE_KR.md](./MINIO_SECURITY_GUIDE_KR.md)** | 보안 및 모범 사례 | 보안 팀, 프로덕션 |

### 🚀 빠른 시작 스크립트

| 스크립트 | 목적 | 사용 사례 |
|--------|---------|----------|
| `deploy-minio-distributed.sh` | **권장** - 모든 클러스터 크기를 적절히 처리 | 가장 일반적인 배포 |
| `deploy-minio-working.sh` | 일반 배포 스크립트 | 다중 노드 클러스터 |
| `minio-operations.sh` | 대화형 관리 도구 | 일상적인 운영 |

## 🎯 이 배포가 제공하는 것

### ✅ 기능
- **분산 객체 스토리지** - 모든 클러스터 노드에 걸쳐
- **고가용성** - 자동 장애 조치 기능
- **S3 호환 API** - 원활한 애플리케이션 통합을 위한
- **웹 관리 콘솔** - 쉬운 관리를 위한
- **로컬 스토리지 활용** - 최대 성능을 위한
- **수평 확장성** - 클러스터 성장에 따른
- **외부 접근** - NodePort 서비스를 통한

### 🏗️ 아키텍처 하이라이트
- 안정적인 파드 식별자를 위한 **StatefulSet** 배포
- 최적의 성능을 위한 **로컬 영구 볼륨**
- 노드 간 분산을 위한 **파드 반친화성**
- 자동 복구를 위한 **상태 확인**
- 헤드리스 서비스를 통한 **서비스 디스커버리**

## 🚀 빠른 배포

### 사전 요구사항
```bash
# 클러스터 접근 확인
kubectl cluster-info

# 노드 상태 확인
kubectl get nodes -o wide

# 충분한 리소스 확인 (노드당 2GB RAM, 2 CPU, 10GB 스토리지)
kubectl describe nodes | grep -A 5 "Capacity:"
```

### 원클릭 배포
```bash
# 스크립트를 실행 가능하게 만들기
chmod +x deploy-minio-distributed.sh

# MinIO 배포
./deploy-minio-distributed.sh

# 배포 모니터링
kubectl get pods -n minio-system -w
```

### MinIO 접근
```bash
# 노드 IP 가져오기
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# 접근 URL
echo "MinIO 콘솔: http://$NODE_IP:30901"
echo "MinIO API: http://$NODE_IP:30900"
echo "자격 증명: minioadmin / minioadmin123"
```

## 📊 배포 시나리오

### 시나리오 1: 단일 노드 개발
```bash
# 자동으로 감지되고 구성됨
# - 1개 복제본 (독립형 모드)
# - 사용 가능한 노드에 단일 PV
# - 분산 없음, 하지만 완전한 기능
```

### 시나리오 2: 2노드 프로덕션
```bash
# 소규모 프로덕션 환경에 최적
# - 기본 중복성을 가진 2개 복제본
# - 두 노드에 걸쳐 데이터 분산
# - 단일 노드 장애를 견딜 수 있음
```

### 시나리오 3: 다중 노드 엔터프라이즈
```bash
# 완전한 분산 모드
# - 삭제 코딩을 사용한 4개 이상 복제본
# - 최대 중복성 및 성능
# - 엔터프라이즈급 가용성
```

## 🔧 일반적인 작업

### 배포 상태 확인
```bash
# 파드 상태
kubectl get pods -n minio-system -o wide

# 서비스 상태
kubectl get svc -n minio-system

# 스토리지 상태
kubectl get pvc -n minio-system
```

### MinIO 확장
```bash
# 수평 확장
kubectl scale statefulset minio --replicas=4 -n minio-system

# 필요에 따라 추가 PV 생성
# (자세한 내용은 MINIO_TROUBLESHOOTING_KR.md 참조)
```

### 로그 접근
```bash
# 현재 로그
kubectl logs -f minio-0 -n minio-system

# 이전 컨테이너 로그
kubectl logs minio-0 -n minio-system --previous
```

### 대화형 관리
```bash
# 운영 스크립트 사용
./minio-operations.sh

# 또는 MinIO 셸에 직접 접근
kubectl exec -it minio-0 -n minio-system -- /bin/bash
```

## 🔍 문제 해결 빠른 참조

### 파드가 Pending에서 멈춤
```bash
# 이벤트 확인
kubectl describe pod minio-1 -n minio-system

# 일반적인 원인:
# - 사용 가능한 PV 없음 → 더 많은 PV 생성
# - 노드 taint → toleration 추가 또는 taint 제거
# - 리소스 제약 → 리소스 요청 줄이기
```

### 파드 CrashLoopBackOff
```bash
# 로그 확인
kubectl logs minio-0 -n minio-system

# 일반적인 원인:
# - 권한 문제 → 스토리지 권한 수정
# - 네트워크 문제 → 서비스 엔드포인트 확인
# - 구성 오류 → 환경 변수 확인
```

### 콘솔에 접근할 수 없음
```bash
# 서비스 확인
kubectl get svc minio-console -n minio-system

# 연결 테스트
kubectl port-forward svc/minio-console 9001:9001 -n minio-system

# 포트 30901에 대한 방화벽/보안 그룹 확인
```

## 🔒 보안 고려사항

### 프로덕션을 위한 즉시 조치
1. **기본 자격 증명 변경**
   ```bash
   # 강력한 자격 증명 생성
   MINIO_ACCESS_KEY=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
   MINIO_SECRET_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
   ```

2. **TLS 활성화**
   ```bash
   # TLS 시크릿 생성 및 StatefulSet 업데이트
   # (자세한 내용은 MINIO_SECURITY_GUIDE_KR.md 참조)
   ```

3. **네트워크 정책 구성**
   ```bash
   # 네트워크 접근 제한
   # (예시는 MINIO_SECURITY_GUIDE_KR.md 참조)
   ```

### 보안 체크리스트
- [ ] 기본 자격 증명 변경됨
- [ ] TLS/SSL 활성화됨
- [ ] 네트워크 정책 구성됨
- [ ] RBAC 권한 설정됨
- [ ] 감사 로깅 활성화됨
- [ ] 백업 암호화 구성됨

## 📈 성능 최적화

### 노드 수준 최적화
```bash
# 커널 매개변수
echo 'vm.dirty_ratio = 5' >> /etc/sysctl.conf
echo 'vm.dirty_background_ratio = 2' >> /etc/sysctl.conf
sysctl -p

# 전용 스토리지 디스크 사용
# SSD 스토리지를 /mnt/minio-data에 마운트
```

### MinIO 구성
```bash
# API 설정 최적화
kubectl exec -it minio-0 -n minio-system -- mc admin config set local api \
    requests_max=1000 \
    requests_deadline=10s
```

## 🔄 백업 및 복구

### 자동화된 백업
```bash
# 일일 백업을 위한 CronJob 설정
# (완전한 예시는 MINIO_SECURITY_GUIDE_KR.md 참조)

# 수동 백업
kubectl exec -it minio-0 -n minio-system -- mc mirror local external-backup
```

### 재해 복구
```bash
# Kubernetes 리소스 백업
kubectl get all,pv,pvc,secrets -n minio-system -o yaml > minio-backup.yaml

# 백업에서 복원
kubectl apply -f minio-backup.yaml
```

## 📞 지원 및 리소스

### 도움 받기
1. **문제 해결 가이드 확인**: [MINIO_TROUBLESHOOTING_KR.md](./MINIO_TROUBLESHOOTING_KR.md)
2. **배포 단계 검토**: [MINIO_DEPLOYMENT_STEPS_KR.md](./MINIO_DEPLOYMENT_STEPS_KR.md)
3. **보안 질문**: [MINIO_SECURITY_GUIDE_KR.md](./MINIO_SECURITY_GUIDE_KR.md)

### 유용한 명령어 참조
```bash
# 배포 상태
kubectl get all -n minio-system

# 리소스 사용량
kubectl top pods -n minio-system

# 이벤트 및 로그
kubectl get events -n minio-system --sort-by='.lastTimestamp'
kubectl logs -f deployment/minio -n minio-system

# 대화형 작업
./minio-operations.sh
```

### 외부 리소스
- [MinIO 문서](https://docs.min.io/)
- [Kubernetes 문서](https://kubernetes.io/docs/)
- [MinIO 클라이언트 (mc) 가이드](https://docs.min.io/docs/minio-client-complete-guide.html)

## 🏷️ 버전 정보

- **MinIO 버전**: RELEASE.2024-01-16T16-07-38Z
- **MinIO 클라이언트**: RELEASE.2024-01-13T07-53-27Z
- **Kubernetes**: 1.19+ (1.24+에서 테스트됨)
- **문서 버전**: 1.0

## 📝 기여하기

이 문서를 개선하려면:
1. 환경에서 배포 테스트
2. 문제나 개선사항 문서화
3. 관련 가이드 파일 업데이트
4. 모든 스크립트가 실행 가능하고 기능적인지 확인

---

**🎉 이제 Kubernetes 클러스터에서 MinIO를 분산 모드로 배포할 준비가 되었습니다!**

위의 [빠른 배포](#빠른-배포) 섹션부터 시작하고, 필요에 따라 자세한 가이드를 참조하세요.
