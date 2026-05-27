# Baselink MSA GitOps

Baselink 백엔드 서비스를 EKS에 배포하기 위한 Kubernetes manifest 저장소입니다.

현재는 CI/CD 자동화 전 단계이므로, Terraform으로 인프라를 만든 뒤 GitOps manifest를 수동으로 적용하는 방식으로 사용합니다.

## 현재 범위

- dev 환경 수동 배포
- ECR, EKS, RDS, ElastiCache, SQS 등 인프라는 Terraform에서 관리
- Kubernetes 리소스는 Kustomize 기반으로 배포
- GitHub Actions, Argo CD 같은 자동화는 이후 단계에서 추가 예정

## 디렉터리 구조

```text
gitops/
  base/
    namespace.yaml
    serviceaccount.yaml
    configmap.yaml
    secret.example.yaml
    workloads.yaml
    services.yaml
    kustomization.yaml
  overlays/
    dev/
      kustomization.yaml
  db/
    seed-dev.sql
```

## 서비스 목록

| 서비스 | 포트 | 역할 |
| --- | ---: | --- |
| auth-service | 8081 | 회원가입, 로그인, JWT 발급 |
| game-service | 8082 | 경기 및 좌석 조회 |
| admin-service | 8083 | 관리자용 경기/좌석 데이터 생성 |
| waiting-room-service | 8084 | Redis 기반 대기열 |
| ticket-worker-service | 8085 | SQS 메시지 소비 및 예매 확정 |
| seat-lock-service | 8086 | Redis 기반 좌석 잠금 |
| ticket-service | 8087 | 예매 요청 저장 및 SQS 메시지 발행 |
| order-service | 8001 | 주문 API |
| ai-chatbot-service | 8000 | AI 챗봇 API |

## 배포 준비

1. Terraform으로 dev 인프라를 생성합니다.

```bash
cd terraform/env/dev/infra
terraform init
terraform apply
```

필요한 addon 리소스가 있다면 addon도 적용합니다.

```bash
cd ../addon
terraform init
terraform apply
```

2. kubectl을 EKS 클러스터에 연결합니다.

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name baselink-dev
kubectl get nodes
```

3. 백엔드 이미지를 ECR에 빌드 및 push합니다.

예시:

```bash
aws ecr get-login-password --region ap-northeast-2 \
  | docker login --username AWS --password-stdin 740831361032.dkr.ecr.ap-northeast-2.amazonaws.com

docker build -t auth-service:dev ./backend/auth-service
docker tag auth-service:dev 740831361032.dkr.ecr.ap-northeast-2.amazonaws.com/dev-auth-service:dev
docker push 740831361032.dkr.ecr.ap-northeast-2.amazonaws.com/dev-auth-service:dev
```

4. Kubernetes Secret을 준비합니다.

`base/secret.example.yaml`은 예시 파일입니다. 실제 비밀번호나 토큰은 Git에 올리지 않습니다.

dev 환경에서는 RDS Secret Manager 값을 읽어서 `backend-secret`을 클러스터에 생성했습니다.

필수 Secret key:

```text
SPRING_DATASOURCE_USERNAME
SPRING_DATASOURCE_PASSWORD
APP_JWT_SECRET
```

## 수동 배포

```bash
kubectl apply -k gitops/overlays/dev
kubectl get pods -n baselink-dev
kubectl get svc -n baselink-dev
```

모든 Pod가 `1/1 Running`이면 기본 배포가 완료된 상태입니다.

## DB 구조

dev RDS PostgreSQL에는 다음 schema와 table이 생성됩니다.

```text
auth_schema
  users

game_schema
  stadiums
  games
  seat_sections

ticket_schema
  seats
  game_seats
  reservations
  waiting_room_policies

order_schema
  alcohol_menus

chatbot_schema
  faq
```

현재 dev 환경에서는 Spring JPA 설정 `ddl-auto=update`를 사용하므로, 애플리케이션이 실행될 때 Entity 기준으로 테이블이 생성됩니다.

주의할 점:

- RDS 인스턴스는 Terraform이 생성합니다.
- schema는 수동 SQL 또는 별도 초기화 작업으로 생성해야 합니다.
- table은 현재 dev 기준으로 Spring JPA가 생성합니다.
- 운영 환경에서는 `ddl-auto=update` 대신 Flyway 또는 Liquibase 같은 migration 도구를 사용하는 것이 좋습니다.

## DB Seed 데이터

dev 환경에서 API 테스트를 하려면 최소 초기 데이터가 필요합니다.

Seed 파일:

```text
gitops/db/seed-dev.sql
```

이 파일은 다음 데이터를 생성합니다.

```text
관리자 계정
  email: admin@baselink.dev
  password: Password123!
  role: ADMIN

구장
  Jamsil Baseball Stadium

경기
  Doosan Bears vs LG Twins

좌석 구역
  First Base A

좌석
  A-1

경기좌석
  gameId=1, seatId=1, status=AVAILABLE
```

### Seed 실행 방법

RDS는 private subnet에 있으므로 로컬 PC에서 바로 접속되지 않을 수 있습니다. 가장 쉬운 방법은 EKS 내부에 임시 PostgreSQL Pod를 띄워서 실행하는 방식입니다.

1. 임시 psql Pod 생성

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: psql-inspect
  namespace: baselink-dev
spec:
  restartPolicy: Never
  containers:
    - name: psql
      image: postgres:16
      command: ["sleep", "3600"]
      env:
        - name: PGHOST
          value: baselink-dev-postgres.cves8emympgn.ap-northeast-2.rds.amazonaws.com
        - name: PGPORT
          value: "5432"
        - name: PGDATABASE
          value: baseball_platform
        - name: PGUSER
          valueFrom:
            secretKeyRef:
              name: backend-secret
              key: SPRING_DATASOURCE_USERNAME
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: backend-secret
              key: SPRING_DATASOURCE_PASSWORD
EOF
```

2. Pod 준비 확인

```bash
kubectl wait --for=condition=Ready pod/psql-inspect -n baselink-dev --timeout=90s
```

3. seed SQL 실행

Linux/macOS/Git Bash:

```bash
kubectl exec -i -n baselink-dev psql-inspect -- psql -v ON_ERROR_STOP=1 < gitops/db/seed-dev.sql
```

Windows PowerShell:

```powershell
Get-Content .\gitops\db\seed-dev.sql | kubectl exec -i -n baselink-dev psql-inspect -- psql -v ON_ERROR_STOP=1
```

4. 데이터 확인

```bash
kubectl exec -n baselink-dev psql-inspect -- psql -c "select * from game_schema.games;"
kubectl exec -n baselink-dev psql-inspect -- psql -c "select * from ticket_schema.game_seats;"
kubectl exec -n baselink-dev psql-inspect -- psql -c "select user_id, email, role, status from auth_schema.users;"
```

5. 임시 Pod 삭제

```bash
kubectl delete pod psql-inspect -n baselink-dev
```

## API 테스트

### 내부 호출 테스트

클러스터 내부에서 서비스 DNS로 호출합니다.

```bash
kubectl run curl-auth-health --rm -i --restart=Never \
  --image=curlimages/curl:8.8.0 \
  -n baselink-dev \
  -- http://auth-service:8081/health
```

경기 목록 조회:

```bash
kubectl run curl-game-list --rm -i --restart=Never \
  --image=curlimages/curl:8.8.0 \
  -n baselink-dev \
  -- http://game-service:8082/api/games
```

경기 좌석 조회:

```bash
kubectl run curl-game-seats --rm -i --restart=Never \
  --image=curlimages/curl:8.8.0 \
  -n baselink-dev \
  -- http://game-service:8082/api/games/1/seats
```

### 로컬 port-forward 테스트

현재 서비스는 `ClusterIP`이므로 외부 공개 URL이 없습니다. 로컬에서 테스트하려면 port-forward를 사용합니다.

```bash
kubectl port-forward -n baselink-dev svc/auth-service 18081:8081
curl http://localhost:18081/health
```

다른 터미널에서 game-service도 테스트할 수 있습니다.

```bash
kubectl port-forward -n baselink-dev svc/game-service 18082:8082
curl http://localhost:18082/api/games
```

## 예매 흐름 확인

기본 흐름:

```text
1. auth-service에서 로그인
2. game-service에서 경기/좌석 조회
3. waiting-room-service에서 대기열 진입
4. seat-lock-service에서 좌석 잠금
5. ticket-service에서 예약 요청 저장
6. ticket-service가 SQS 메시지 발행
7. ticket-worker-service가 SQS 메시지 소비
8. ticket_schema.reservations 상태가 CONFIRMED로 변경
```

SQS 처리 로그 확인:

```bash
kubectl logs deployment/ticket-service -n baselink-dev --since=5m
kubectl logs deployment/ticket-worker-service -n baselink-dev --since=5m
```

정상 로그 예시:

```text
ticket-service: 예매 확정 요청 메시지 발송 완료
ticket-worker-service: SQS 메시지 파싱 완료
ticket-worker-service: 예매 최종 확정 완료
```

## 참고 사항

- `ticket-service`는 `ticket-confirm-queue` SQS queue로 메시지를 보냅니다.
- `ticket-worker-service`는 같은 SQS queue를 구독합니다.
- `waiting-room-service`, `seat-lock-service`는 Redis가 필요합니다.
- DB를 사용하는 Spring 서비스는 `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD` 값을 사용합니다.
- Redis를 사용하는 서비스는 `SPRING_DATA_REDIS_HOST`, `SPRING_DATA_REDIS_PORT` 값을 사용합니다.
- 실제 Secret 파일은 Git에 커밋하지 않습니다.
- 추후 운영 환경에서는 External Secrets, Sealed Secrets, Flyway/Liquibase 도입을 검토합니다.
