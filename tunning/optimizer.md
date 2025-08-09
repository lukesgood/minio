## 주요 기능

1. 자동 OS 감지
• Ubuntu, Debian, CentOS, RHEL, Rocky Linux, AlmaLinux 지원
• OS별 최적화된 설정 적용

2. 포괄적인 최적화 설정
• **네트워크 성능**: 버퍼 크기, TCP 최적화, BBR 혼잡 제어
• **메모리 관리**: dirty ratio, swappiness, 캐시 압력 조정
• **파일시스템**: 파일 디스크립터 한계 증가
• **I/O 스케줄러**: SSD 최적화를 위한 'none' 스케줄러
• **시스템 한계**: nofile, nproc, memlock 설정
• **systemd 설정**: 기본 한계값 조정

3. 안전한 운영
• 자동 백업 생성 (/etc/sysctl.d/backup/)
• Dry-run 모드로 미리보기
• 설정 복원 기능
• 단계별 확인 프로세스

## 사용 방법

bash
# 현재 설정 확인
sudo ./minio_kernel_optimize.sh --check

# 변경사항 미리보기 (실제 적용 안함)
sudo ./minio_kernel_optimize.sh --dry-run

# 대화형 모드로 최적화 실행
sudo ./minio_kernel_optimize.sh

# 확인 없이 바로 적용
sudo ./minio_kernel_optimize.sh --force

# 백업에서 설정 복원
sudo ./minio_kernel_optimize.sh --restore

# 도움말 보기
./minio_kernel_optimize.sh --help


## 적용되는 주요 최적화 설정

네트워크 최적화
• net.core.rmem_max = 134217728 (128MB 수신 버퍼)
• net.core.wmem_max = 134217728 (128MB 송신 버퍼)
• net.ipv4.tcp_congestion_control = bbr (BBR 혼잡 제어)

메모리 최적화
• vm.dirty_ratio = 5 (더티 페이지 비율 감소)
• vm.swappiness = 1 (스왑 사용 최소화)
• vm.vfs_cache_pressure = 50 (캐시 압력 조정)

파일시스템 최적화
• fs.file-max = 1048576 (최대 파일 디스크립터)
• * soft/hard nofile 1048576 (사용자별 파일 한계)

I/O 최적화
• elevator=none (SSD용 I/O 스케줄러)
