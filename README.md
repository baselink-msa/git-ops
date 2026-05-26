# Baselink MSA GitOps

Baselink 백엔드 서비스를 EKS에 배포하기 위한 Kubernetes manifest 저장소입니다.

## 현재 범위

- dev 환경 수동 배포
- ECR, EKS, ALB Controller 등 인프라는 Terraform에서 관리
- Kubernetes 리소스는 Kustomize 기반으로 배포
- CI/CD 자동화는 추후 추가 예정

## 디렉터리 구조

```text
gitops/
  base/
    namespace.yaml
    serviceaccount.yaml
    configmap.yaml
    ingress.yaml
    secret.example.yaml
    workloads.yaml
    services.yaml
    kustomization.yaml
  overlays/
    dev/
      kustomization.yaml
```

## 서비스 목록

| 서비스 | 포트 | 역할 |
| --- | ---: | --- |
| auth-service | 8081 | 로그인, 회원가입, JWT |
| game-service | 8082 | 경기 및 좌석 조회 |
| admin-service | 8083 | 관리자 API |
| waiting-room-service | 8084 | Redis 기반 대기열 |
| ticket-worker-service | 8085 | 티켓 확정 SQS consumer |
| seat-lock-service | 8086 | Redis 기반 좌석 락 |
| ticket-service | 8087 | 티켓 예매 API 및 SQS producer |
| order-service | 8001 | 주문 API |
| ai-chatbot-service | 8000 | AI 챗봇 API |

## 배포 전 준비

1. Terraform으로 dev 인프라와 addon을 먼저 적용합니다.

```bash
cd terraform/env/dev/infra
terraform init
terraform apply

cd ../addon
terraform init
terraform apply
```

2. kubectl을 EKS 클러스터에 연결합니다.

```bash
aws eks update-kubeconfig --region ap-northeast-2 --name baselink-dev
kubectl get nodes
```

3. 백엔드 이미지를 ECR에 빌드/푸시합니다.

예시:

```bash
aws ecr get-login-password --region ap-northeast-2 \
  | docker login --username AWS --password-stdin 740831361032.dkr.ecr.ap-northeast-2.amazonaws.com

docker build -t auth-service:dev ./backend/auth-service
docker tag auth-service:dev 740831361032.dkr.ecr.ap-northeast-2.amazonaws.com/dev-auth-service:dev
docker push 740831361032.dkr.ecr.ap-northeast-2.amazonaws.com/dev-auth-service:dev
```

4. 실제 Secret을 클러스터에 수동 적용합니다.

```bash
cp base/secret.example.yaml base/secret.yaml
```

`base/secret.yaml`에 실제 값을 채운 뒤 적용합니다.

```bash
kubectl apply -f base/secret.yaml
```

`secret.yaml`은 커밋하지 않습니다.

## 수동 배포

```bash
kubectl apply -k overlays/dev
kubectl get pods -n baselink-dev
kubectl get svc -n baselink-dev
kubectl get ingress -n baselink-dev
```

## Ingress / ALB 확인

`base/ingress.yaml`은 AWS Load Balancer Controller를 통해 internet-facing ALB를 생성합니다.

라우팅 구조:

```text
/api/auth        -> auth-service:8081
/api/games       -> game-service:8082
/api/admin       -> admin-service:8083
/api/waiting-room -> waiting-room-service:8084
/api/chatbot     -> ai-chatbot-service:8000
/api/orders      -> order-service:8001
/api/seats/locks -> seat-lock-service:8086
/api/tickets     -> ticket-service:8087
```

ALB 주소 확인:

```bash
kubectl get ingress -n baselink-dev baselink-api
kubectl describe ingress -n baselink-dev baselink-api
```

ALB가 `active` 상태가 된 뒤 API를 확인합니다.

```bash
curl http://<ALB_DNS_NAME>/api/auth/health
```

CloudFront를 사용할 때는 `/api/*` behavior를 이 ALB origin으로 연결합니다.

## 로컬 포트포워딩 테스트

```bash
kubectl port-forward -n baselink-dev svc/auth-service 8081:8081
curl http://localhost:8081/health
```

## 참고 사항

- `ticket-service`는 `ticket-confirm-queue` SQS 큐로 메시지를 보냅니다.
- `ticket-worker-service`는 같은 SQS 큐를 구독합니다.
- `waiting-room-service`, `seat-lock-service`는 Redis가 필요합니다.
- DB를 사용하는 Spring 서비스는 `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD` 값을 사용합니다.
- Redis를 사용하는 Spring 서비스는 `SPRING_DATA_REDIS_HOST`, `SPRING_DATA_REDIS_PORT` 값을 사용합니다.
- 커밋된 `secret.example.yaml`은 템플릿입니다. 실제 Secret은 수동 적용하거나 추후 External Secrets, Sealed Secrets 등으로 관리합니다.
