# BaseLink GitOps

BaseLink 백엔드 서비스를 EKS dev 환경에 배포하기 위한 Kubernetes manifest 저장소입니다. Kustomize overlay를 기준으로 배포 이미지를 관리하며, Argo CD 연동을 전제로 합니다.

## 현재 범위

- `baselink-dev` 네임스페이스 배포
- 9개 백엔드 서비스 Deployment/Service/Ingress
- IRSA 기반 `backend-runtime` ServiceAccount
- RDS, ElastiCache, SQS, ECR은 Terraform에서 생성
- `db/seed-dev.sql`로 dev RDS 초기 스키마와 데이터 생성
- CI가 `overlays/dev/kustomization.yaml`의 이미지 태그를 갱신

## 디렉터리 구조

```text
base/
  namespace.yaml
  serviceaccount.yaml
  configmap.yaml
  secret.example.yaml
  workloads.yaml
  services.yaml
  ingress.yaml
  ingress-argocd.yaml
  kustomization.yaml
overlays/
  dev/
    kustomization.yaml
db/
  seed-dev.sql
```

## 서비스

| 서비스 | 포트 | 역할 |
| --- | ---: | --- |
| auth-service | 8081 | 회원가입, 로그인, JWT |
| game-service | 8082 | 경기/구장/좌석 조회 |
| admin-service | 8083 | 관리자 CRUD |
| waiting-room-service | 8084 | Redis 대기열 |
| ticket-worker-service | 8085 | SQS 예매 메시지 검증 |
| seat-lock-service | 8086 | Redis 좌석 잠금, DB 상태 동기화 |
| ticket-service | 8087 | 예매 생성/조회/확정/취소 |
| order-service | 8001 | 주류 주문 |
| ai-chatbot-service | 8000 | FAQ + AI 챗봇 |

## 배포 전 준비

1. Terraform으로 dev 인프라를 생성합니다.

```bash
cd ../baselink-terraform
./scripts/infra-up.sh
```

2. AWS 인증과 kubeconfig를 준비합니다.

```bash
aws login
aws eks update-kubeconfig --region ap-northeast-2 --name baselink-dev
kubectl get nodes
```

3. Secret을 생성합니다.

`base/secret.example.yaml`은 예시입니다. 실제 값은 커밋하지 않습니다.

필수 키:

```text
SPRING_DATASOURCE_USERNAME
SPRING_DATASOURCE_PASSWORD
APP_JWT_SECRET
```

## Kustomize 확인 및 적용

로컬 렌더링:

```bash
kubectl kustomize overlays/dev
```

수동 적용:

```bash
kubectl apply -k overlays/dev
```

상태 확인:

```bash
kubectl get deploy,pods,svc,ingress -n baselink-dev
kubectl rollout status deployment/auth-service -n baselink-dev
kubectl rollout status deployment/game-service -n baselink-dev
kubectl rollout status deployment/admin-service -n baselink-dev
kubectl rollout status deployment/waiting-room-service -n baselink-dev
kubectl rollout status deployment/ticket-worker-service -n baselink-dev
kubectl rollout status deployment/seat-lock-service -n baselink-dev
kubectl rollout status deployment/ticket-service -n baselink-dev
kubectl rollout status deployment/order-service -n baselink-dev
kubectl rollout status deployment/ai-chatbot-service -n baselink-dev
```

## Argo CD 확인

```bash
kubectl get applications -A
kubectl get pods,svc,ingress -n argocd
```

`base/ingress-argocd.yaml`은 ALB `/argocd` 경로를 `argocd` 네임스페이스의 `argocd-server`로 연결합니다. 각 리소스가 namespace를 명시하므로 overlay에서는 전역 `namespace`를 사용하지 않습니다.

## 이미지 태그

`overlays/dev/kustomization.yaml`에서 서비스별 ECR 이미지와 Git SHA 태그를 관리합니다.

```text
740831361032.dkr.ecr.ap-northeast-2.amazonaws.com/dev-<service-name>:<github.sha>
```

현재 overlay는 9개 서비스 모두 ECR 이미지로 치환합니다.

## DB Seed

`db/seed-dev.sql`은 RDS를 새로 만들었을 때 dev 환경을 바로 테스트할 수 있도록 스키마, 테이블, 시드 데이터를 함께 생성합니다.

포함 내용:

- `auth_schema`, `game_schema`, `ticket_schema`, `order_schema`, `chatbot_schema`
- 관리자 계정
  - email: `admin@baselink.dev`
  - password: `Password123!`
- 구장 5개
- 구장별 5개 좌석 구역
- 구장별 200석
- 경기 2개
- 경기별 `game_seats` 자동 연결
- `game_seats.status` 체크 제약조건: `AVAILABLE`, `SOLD`, `BLOCKED`, `LOCKED`
- 대기열 정책, 주류 메뉴, FAQ

임시 Pod로 실행:

```bash
kubectl run psql-seed --rm -i --restart=Never -n baselink-dev \
  --image=postgres:16-alpine -- sh -c \
  'PGPASSWORD="$PASS" psql -h $HOST -U baseball -d baseball_platform -v ON_ERROR_STOP=1 -f -' < db/seed-dev.sql
```

Secret 기반으로 점검 Pod를 만들어 실행하려면:

```bash
kubectl run psql-inspect -n baselink-dev --restart=Never --image=postgres:16-alpine -- sleep 3600
kubectl wait --for=condition=Ready pod/psql-inspect -n baselink-dev --timeout=90s
kubectl exec -i -n baselink-dev psql-inspect -- psql -h "$HOST" -U baseball -d baseball_platform -v ON_ERROR_STOP=1 < db/seed-dev.sql
kubectl delete pod psql-inspect -n baselink-dev
```

데이터 확인 쿼리:

```bash
kubectl exec -n baselink-dev psql-inspect -- psql -c "select count(*) from game_schema.stadiums;"
kubectl exec -n baselink-dev psql-inspect -- psql -c "select stadium_id, count(*) from ticket_schema.seats group by stadium_id order by stadium_id;"
kubectl exec -n baselink-dev psql-inspect -- psql -c "select game_id, status, count(*) from ticket_schema.game_seats group by game_id, status order by game_id, status;"
```

## API 스모크 테스트

클러스터 내부에서 호출:

```bash
kubectl run curl-auth-health --rm -i --restart=Never \
  --image=curlimages/curl:8.8.0 \
  -n baselink-dev \
  -- http://auth-service:8081/health

kubectl run curl-games --rm -i --restart=Never \
  --image=curlimages/curl:8.8.0 \
  -n baselink-dev \
  -- http://game-service:8082/api/games
```

로컬 port-forward:

```bash
kubectl port-forward -n baselink-dev svc/game-service 18082:8082
curl http://localhost:18082/api/games
```

## 이번 점검 메모

- `kubectl kustomize overlays/dev` 렌더링은 정상입니다.
- 실시간 `kubectl get ...`, ECR 조회, Argo CD Application 조회는 AWS CLI 세션 만료 시 실패합니다. `aws login` 후 다시 실행해야 합니다.
- 로컬에 `gh` CLI가 없으면 GitHub Actions 실행 이력 조회는 GitHub UI에서 확인합니다.

## 알려진 이슈

- `KNOWLEDGE_BASE_ID`는 현재 placeholder이므로 Bedrock 연동 시 실제 값으로 교체해야 합니다.
- Redis TTL 만료만으로 좌석 잠금이 풀릴 경우 DB `game_seats.status=LOCKED`가 남을 수 있습니다.
- 운영 환경에서는 `ddl-auto=update` 대신 Flyway/Liquibase 도입을 권장합니다.
