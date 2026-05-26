# Baselink MSA GitOps

This repository stores Kubernetes manifests for manually deploying the backend services to EKS.

## Current Scope

- Manual deployment only
- ECR and EKS are created by Terraform
- CI/CD and automation will be added later
- Use Kustomize with `kubectl apply -k`

## Directory Structure

```text
gitops/
  base/
    namespace.yaml
    configmap.yaml
    secret.example.yaml
    workloads.yaml
    services.yaml
    kustomization.yaml
  overlays/
    dev/
      kustomization.yaml
```

## Services

| Service | Port | Purpose |
| --- | ---: | --- |
| auth-service | 8081 | Login, signup, JWT |
| game-service | 8082 | Game and seat lookup |
| admin-service | 8083 | Admin APIs |
| waiting-room-service | 8084 | Redis-based waiting room |
| ticket-worker-service | 8085 | SQS consumer for ticket confirmation |
| seat-lock-service | 8086 | Redis-based seat lock |
| ticket-service | 8087 | Ticket reservation API and SQS producer |
| order-service | 8001 | Order API |
| ai-chatbot-service | 8000 | AI chatbot API |

## Before Deploying

1. Create infrastructure with Terraform:

```powershell
cd terraform/env/dev/infra
terraform init
terraform apply
```

2. Connect kubectl to EKS:

```powershell
aws eks update-kubeconfig --region ap-northeast-2 --name <eks-cluster-name>
kubectl get nodes
```

3. Build and push backend images to ECR manually.

Example:

```powershell
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-northeast-2.amazonaws.com
docker build -t auth-service:dev ./backend/auth-service
docker tag auth-service:dev 740831361032.dkr.ecr.ap-northeast-2.amazonaws.com/dev-auth-service:dev
docker push 740831361032.dkr.ecr.ap-northeast-2.amazonaws.com/dev-auth-service:dev
```

Java services currently need Dockerfiles before the image build step can work.
The ECR repositories are named with the environment prefix, for example `dev-auth-service`.

4. Copy the example secret and fill real values:

```powershell
Copy-Item gitops/base/secret.example.yaml gitops/base/secret.yaml
```

Do not commit `secret.yaml`.

Apply the secret manually before deploying the workloads:

```powershell
kubectl apply -f gitops/base/secret.yaml
```

5. Update placeholder values in:

- `base/configmap.yaml`
- `base/secret.yaml`
- `overlays/dev/kustomization.yaml`

## Manual Deploy

```powershell
kubectl apply -k gitops/overlays/dev
kubectl get pods -n baselink-dev
kubectl get svc -n baselink-dev
```

## Local Test with Port Forward

```powershell
kubectl port-forward -n baselink-dev svc/auth-service 8081:8081
curl http://localhost:8081/health
```

## Important Notes

- `ticket-service` sends messages to the SQS queue named `ticket-confirm-queue`.
- `ticket-worker-service` listens to the same queue name.
- `waiting-room-service` and `seat-lock-service` require Redis.
- DB-related Spring services use `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, and `SPRING_DATASOURCE_PASSWORD`.
- Redis-related Spring services use `SPRING_DATA_REDIS_HOST` and `SPRING_DATA_REDIS_PORT`.
- The committed `secret.example.yaml` is only a template. Real secret values should be applied manually or managed later with External Secrets, Sealed Secrets, or another secret manager.
