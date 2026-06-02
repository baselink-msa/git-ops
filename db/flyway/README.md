# Flyway 수동 복구 참고 자료

현재 기본 migration은 `auth-service` 시작 시 자동으로 실행됩니다.

```text
backend/auth-service/src/main/resources/db/migration/
```

이 디렉터리는 로컬 검증과 비상 수동 복구를 위한 참고 자료입니다. 현재 Kustomize 배포에는 포함하지 않았습니다. 수동 Job을 공유 dev RDS에 적용하기 전에는 팀원들과 적용 시점을 맞춰야 합니다.

## 참고 파일 구성

```text
gitops/db/flyway/
  README.md
  job.example.yaml
  sql/
    V1__create_schemas_and_tables.sql
    R__seed_dev_data.sql
```

각 파일의 역할은 다음과 같습니다.

```text
V1__create_schemas_and_tables.sql
  auth_schema, game_schema, ticket_schema, order_schema, chatbot_schema 생성
  users, games, seats, reservations 등 주요 테이블 생성

R__seed_dev_data.sql
  dev 관리자 계정 생성
  구장, 경기, 좌석 구역, 좌석, 경기좌석 생성
  메뉴, FAQ, 대기열 정책 생성

job.example.yaml
  EKS 안에서 Flyway를 실행하기 위한 Kubernetes Job 예시
```

## 현재 기본 흐름

```text
Terraform apply
-> backend-secret 생성
-> backend 배포
-> auth-service 시작
-> Flyway migration 자동 실행
-> schema/table/seed 자동 준비
```

## 로컬 Docker 테스트

공유 RDS를 건드리지 않고 로컬에서 migration을 검증하려면 Docker PostgreSQL과 Flyway Docker 이미지를 사용하면 됩니다.

### 1. PostgreSQL 테스트 컨테이너 실행

```powershell
docker run --name baselink-postgres-test `
  -e POSTGRES_USER=baseball `
  -e POSTGRES_PASSWORD=baseball `
  -e POSTGRES_DB=baseball_platform `
  -p 15432:5432 `
  -d postgres:16
```

준비 상태 확인:

```powershell
docker exec baselink-postgres-test pg_isready -U baseball -d baseball_platform
```

정상 예시:

```text
/var/run/postgresql:5432 - accepting connections
```

### 2. 기존 seed-dev.sql 단독 실행 검증

`gitops/db/seed-dev.sql`은 Flyway 없이도 dev DB를 복구할 수 있는 단일 SQL 파일입니다.

```powershell
Get-Content .\gitops\db\seed-dev.sql |
  docker exec -i baselink-postgres-test `
    psql -U baseball -d baseball_platform -v ON_ERROR_STOP=1
```

주요 데이터 확인:

```powershell
docker exec baselink-postgres-test `
  psql -U baseball -d baseball_platform -v ON_ERROR_STOP=1 `
  -c "select count(*) as users from auth_schema.users;
      select count(*) as stadiums from game_schema.stadiums;
      select count(*) as seat_sections from game_schema.seat_sections;
      select count(*) as seats from ticket_schema.seats;
      select count(*) as games from game_schema.games;
      select count(*) as game_seats from ticket_schema.game_seats;
      select count(*) as menus from order_schema.alcohol_menus;
      select count(*) as faqs from chatbot_schema.faq;
      select email, role, status from auth_schema.users order by user_id;"
```

현재 검증된 예상 결과:

```text
users: 1
stadiums: 5
seat_sections: 25
seats: 1000
games: 2
game_seats: 400
menus: 6
faqs: 7

admin@baselink.dev / ADMIN / ACTIVE
```

`seed-dev.sql`은 재실행 가능하도록 작성되어 있으므로, 같은 명령을 한 번 더 실행해도 중복 오류가 없어야 합니다.

### 3. Flyway migration 검증

깨끗한 DB에서 Flyway를 검증하려면 기존 테스트 컨테이너를 삭제하고 다시 실행합니다.

```powershell
docker rm -f baselink-postgres-test
```

```powershell
docker run --name baselink-postgres-test `
  -e POSTGRES_USER=baseball `
  -e POSTGRES_PASSWORD=baseball `
  -e POSTGRES_DB=baseball_platform `
  -p 15432:5432 `
  -d postgres:16
```

Flyway 실행:

```powershell
docker run --rm `
  -v "${PWD}\backend\auth-service\src\main\resources\db\migration:/flyway/sql" `
  flyway/flyway:10-alpine `
  -url=jdbc:postgresql://host.docker.internal:15432/baseball_platform `
  -user=baseball `
  -password=baseball `
  -connectRetries=30 `
  migrate
```

정상 실행 시 다음 migration이 적용됩니다.

```text
V1__create_schemas_and_tables.sql
V2__create_ticket_open_schedule.sql
V3__add_ticket_uniqueness_constraints.sql
R__seed_dev_data.sql
```

Flyway 적용 기록 확인:

```powershell
docker exec baselink-postgres-test `
  psql -U baseball -d baseball_platform -v ON_ERROR_STOP=1 `
  -c "select installed_rank, version, description, type, success
      from public.flyway_schema_history
      order by installed_rank;"
```

정상 예시:

```text
installed_rank | version | description                | type | success
1              | 1       | create schemas and tables          | SQL  | true
2              | 2       | create ticket open schedule        | SQL  | true
3              | 3       | add ticket uniqueness constraints  | SQL  | true
4              |         | seed dev data                      | SQL  | true
```

Flyway 재실행 검증:

```powershell
docker run --rm `
  -v "${PWD}\backend\auth-service\src\main\resources\db\migration:/flyway/sql" `
  flyway/flyway:10-alpine `
  -url=jdbc:postgresql://host.docker.internal:15432/baseball_platform `
  -user=baseball `
  -password=baseball `
  -connectRetries=30 `
  migrate
```

정상이라면 다음과 비슷하게 출력됩니다.

```text
Schema "public" is up to date. No migration necessary.
```

### 4. 테스트 컨테이너 정리

로컬 테스트가 끝나면 컨테이너를 삭제합니다.

```powershell
docker rm -f baselink-postgres-test
```

## EKS에서 Flyway Job으로 실행하는 방법

이 방식은 나중에 팀원들과 적용 시점을 맞춘 뒤 사용합니다.

먼저 migration SQL을 ConfigMap으로 만듭니다.

```bash
kubectl create configmap flyway-sql \
  --from-file=gitops/db/flyway/sql \
  -n baselink-dev \
  --dry-run=client -o yaml | kubectl apply -f -
```

Flyway Job 실행:

```bash
kubectl apply -f gitops/db/flyway/job.example.yaml
kubectl wait --for=condition=complete job/db-migration -n baselink-dev --timeout=180s
kubectl logs job/db-migration -n baselink-dev
```

Job은 한 번 실행하고 끝나는 리소스입니다. 다시 실행하려면 기존 Job을 삭제해야 합니다.

```bash
kubectl delete job db-migration -n baselink-dev
```

## 수동 복구 검증 순서

```text
1. Flyway Job으로 schema/table/seed 생성 검증
2. backend 서비스 정상 기동 확인
3. API 테스트 확인
4. destroy/apply 후 auth-service 시작만으로 DB 복구되는지 검증
```

`ddl-auto=validate`는 Hibernate가 테이블을 직접 만들지 않고, Entity와 DB 구조가 맞는지만 검사합니다.  
즉 DB 구조 생성 책임은 Flyway가 갖고, 애플리케이션은 구조가 맞는지 확인만 하게 됩니다.

## 주의 사항

- 이 Flyway Job은 아직 현재 Kustomize 배포에 포함되어 있지 않습니다.
- 공유 dev RDS에 적용하기 전에는 팀원들과 시간을 맞춰야 합니다.
- 현재 `seed-dev.sql`과 Flyway SQL은 dev 환경 복구용입니다.
- 운영 환경에서는 dev seed 데이터를 그대로 사용하면 안 됩니다.
- 기본 migration SQL의 기준은 `backend/auth-service/src/main/resources/db/migration/`입니다.
