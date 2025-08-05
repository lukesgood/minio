# Kubernetes 2노드 클러스터 설정

이 저장소는 Ubuntu에서 kubeadm을 사용하여 2노드 Kubernetes 클러스터를 설정하고 Kubernetes 대시보드를 활성화하는 스크립트를 포함합니다.

## 사전 요구사항

- 2대의 Ubuntu 머신 (18.04 이상)
- 각 머신당 최소 2GB RAM과 2개 CPU
- 머신 간 네트워크 연결
- 두 머신 모두에서 sudo 권한
- 각 머신의 고유한 호스트명

## 아키텍처

```
┌─────────────────┐    ┌─────────────────┐
│   마스터 노드   │    │   워커 노드     │
│                 │    │                 │
│ - API 서버      │◄──►│ - kubelet       │
│ - etcd          │    │ - kube-proxy    │
│ - 컨트롤러      │    │ - 컨테이너      │
│ - 스케줄러      │    │   런타임        │
│ - 대시보드      │    │                 │
└─────────────────┘    └─────────────────┘
```

## 빠른 시작

1. **스크립트 복제/다운로드** (두 머신 모두에서)
2. **공통 설정 실행** (두 머신 모두에서):
   ```bash
   chmod +x common-setup.sh
   ./common-setup.sh
   ```

3. **마스터 노드 초기화**:
   ```bash
   chmod +x master-setup.sh
   ./master-setup.sh
   ```

4. **워커 노드 조인** (마스터에서 출력된 명령어 사용):
   ```bash
   chmod +x worker-setup.sh
   ./worker-setup.sh sudo kubeadm join <마스터-ip>:6443 --token <토큰> --discovery-token-ca-cert-hash sha256:<해시>
   ```

5. **대시보드 설치** (마스터에서):
   ```bash
   chmod +x dashboard-setup.sh
   ./dashboard-setup.sh
   ```

## 스크립트 상세 설명

### common-setup.sh
- 시스템 패키지 업데이트
- 스왑 비활성화
- 커널 모듈 및 sysctl 매개변수 구성
- containerd 설치 및 구성
- kubelet, kubeadm, kubectl 설치
- **마스터와 워커 노드 모두에서 실행**

### master-setup.sh
- kubeadm으로 Kubernetes 클러스터 초기화
- kubectl 구성 설정
- Flannel CNI 플러그인 설치
- 워커 노드용 조인 명령어 생성
- **마스터 노드에서만 실행**

### worker-setup.sh
- 제공된 조인 명령어를 사용하여 워커 노드를 클러스터에 조인
- **조인 명령어를 인수로 사용하여 워커 노드에서 실행**

### dashboard-setup.sh
- Kubernetes 대시보드 설치
- cluster-admin 권한을 가진 관리자 서비스 계정 생성
- 액세스 토큰 생성
- **클러스터 설정 후 마스터 노드에서 실행**

## 대시보드 접근

`dashboard-setup.sh` 실행 후:

1. **kubectl 프록시 시작** (마스터 노드에서):
   ```bash
   kubectl proxy
   ```

2. **브라우저에서 대시보드 접근**:
   ```
   http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
   ```

3. **로그인** `/tmp/dashboard-token.txt`에 저장된 토큰 사용

### 외부 접근 (선택사항)

외부 IP에서 대시보드에 접근하려면:
```bash
kubectl patch svc kubernetes-dashboard -n kubernetes-dashboard -p '{"spec":{"type":"NodePort"}}'
kubectl get svc kubernetes-dashboard -n kubernetes-dashboard
```

## 검증 명령어

클러스터 상태 확인:
```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl cluster-info
```

대시보드 확인:
```bash
kubectl get pods -n kubernetes-dashboard
kubectl get svc -n kubernetes-dashboard
```

## 문제 해결

### 일반적인 문제들

1. **스왑이 비활성화되지 않음**: 스왑이 완전히 비활성화되었는지 확인
   ```bash
   sudo swapoff -a
   free -h  # 스왑이 0으로 표시되어야 함
   ```

2. **컨테이너 런타임 문제**: containerd 재시작
   ```bash
   sudo systemctl restart containerd
   sudo systemctl status containerd
   ```

3. **네트워크 문제**: 필요한 포트가 열려있는지 확인
   - 마스터: 6443, 2379-2380, 10250, 10259, 10257
   - 워커: 10250, 30000-32767

4. **파드 네트워크 문제**: Flannel 설치 확인
   ```bash
   kubectl get pods -n kube-flannel
   ```

### 클러스터 리셋 (필요시)

모든 노드에서:
```bash
sudo kubeadm reset
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube/config
```

## 보안 참고사항

- 대시보드 설정은 cluster-admin 권한을 가진 관리자 사용자를 생성합니다
- 프로덕션 환경에서는 더 제한적인 RBAC 정책을 생성하세요
- 인그레스 컨트롤러와 TLS 인증서 사용을 고려하세요
- Kubernetes 구성 요소를 정기적으로 업데이트하세요

## 사용자 정의

### 다른 CNI 플러그인
`master-setup.sh`에서 Flannel을 Calico로 교체:
```bash
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

### 다른 파드 네트워크 CIDR
`master-setup.sh`에서 `--pod-network-cidr`을 변경하고 CNI 구성을 그에 맞게 업데이트하세요.

## 지원

이 스크립트와 관련된 문제는 다음을 확인하세요:
- Kubernetes 문서: https://kubernetes.io/docs/
- kubeadm 문제 해결: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/
- 대시보드 문서: https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
