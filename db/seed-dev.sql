-- =============================================================================
-- Baselink Dev Seed Data
-- RDS를 새로 만들어도 이 파일 하나만 실행하면 최소한의 서비스가 동작합니다.
--
-- 실행 방법 (EKS 클러스터 내부에서):
--   kubectl run psql-seed --rm -i --restart=Never -n baselink-dev \
--     --image=postgres:16-alpine -- sh -c \
--     'PGPASSWORD="$DB_PASS" psql -h $DB_HOST -U baseball -d baseball_platform -f -' < seed-dev.sql
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. 스키마 생성
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS auth_schema;
CREATE SCHEMA IF NOT EXISTS game_schema;
CREATE SCHEMA IF NOT EXISTS ticket_schema;
CREATE SCHEMA IF NOT EXISTS order_schema;
CREATE SCHEMA IF NOT EXISTS chatbot_schema;

-- =============================================================================
-- 2. 테이블 생성 (IF NOT EXISTS — 이미 있으면 스킵)
-- =============================================================================

-- auth
CREATE TABLE IF NOT EXISTS auth_schema.users (
    user_id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(100) NOT NULL,
    role VARCHAR(30) NOT NULL DEFAULT 'USER',
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT now()
);

-- game
CREATE TABLE IF NOT EXISTS game_schema.stadiums (
    stadium_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    location VARCHAR(200),
    capacity INTEGER,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS game_schema.games (
    game_id SERIAL PRIMARY KEY,
    home_team_name VARCHAR(100) NOT NULL,
    away_team_name VARCHAR(100) NOT NULL,
    stadium_id BIGINT REFERENCES game_schema.stadiums(stadium_id),
    game_start_time TIMESTAMP NOT NULL,
    ticket_open_time TIMESTAMP NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'SCHEDULED',
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS game_schema.seat_sections (
    section_id SERIAL PRIMARY KEY,
    stadium_id BIGINT REFERENCES game_schema.stadiums(stadium_id),
    section_name VARCHAR(100) NOT NULL,
    price INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT now()
);

-- ticket
CREATE TABLE IF NOT EXISTS ticket_schema.seats (
    seat_id SERIAL PRIMARY KEY,
    stadium_id BIGINT,
    section_id BIGINT,
    seat_row VARCHAR(10),
    seat_number VARCHAR(10),
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ticket_schema.game_seats (
    game_seat_id SERIAL PRIMARY KEY,
    game_id BIGINT REFERENCES game_schema.games(game_id) ON DELETE CASCADE,
    seat_id BIGINT REFERENCES ticket_schema.seats(seat_id),
    status VARCHAR(30) NOT NULL DEFAULT 'AVAILABLE',
    price INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ticket_schema.reservations (
    reservation_id SERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    game_id BIGINT NOT NULL,
    seat_id BIGINT NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    lock_id VARCHAR(255),
    idempotency_key VARCHAR(255),
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

-- order
CREATE TABLE IF NOT EXISTS order_schema.alcohol_menus (
    menu_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price INTEGER NOT NULL,
    available BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_schema.orders (
    order_id SERIAL PRIMARY KEY,
    user_id BIGINT,
    game_id BIGINT NOT NULL,
    seat_id BIGINT NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'ORDERED',
    total_price INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_schema.order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES order_schema.orders(order_id) ON DELETE CASCADE,
    menu_id BIGINT NOT NULL,
    menu_name VARCHAR(100),
    quantity INTEGER NOT NULL,
    price INTEGER NOT NULL
);

-- chatbot
CREATE TABLE IF NOT EXISTS chatbot_schema.faq (
    faq_id SERIAL PRIMARY KEY,
    category VARCHAR(50),
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT now()
);

-- waiting room
CREATE TABLE IF NOT EXISTS game_schema.waiting_room_policies (
    policy_id SERIAL PRIMARY KEY,
    game_id BIGINT UNIQUE NOT NULL,
    max_enter_per_minute INTEGER NOT NULL DEFAULT 100,
    token_ttl_seconds INTEGER NOT NULL DEFAULT 300,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

-- =============================================================================
-- 3. 시드 데이터
-- =============================================================================

-- 3-1. 관리자 계정 (비밀번호: Password123!)
INSERT INTO auth_schema.users (email, password_hash, name, role, status, created_at)
VALUES ('admin@baselink.dev', '$2a$10$PKjB55l3JArzLe6eKh71UOpcI9/kwQ4cfvjKkG65PahDK9vbXBqPC', 'Dev Admin', 'ADMIN', 'ACTIVE', now())
ON CONFLICT (email) DO UPDATE SET password_hash=EXCLUDED.password_hash, name=EXCLUDED.name, role=EXCLUDED.role, status=EXCLUDED.status;

-- 3-2. 구장 5개
INSERT INTO game_schema.stadiums (stadium_id, name, location, capacity, created_at) VALUES
(1, '잠실야구장', '서울 송파구', 25000, now()),
(2, '광주-KIA 챔피언스 필드', '광주 북구', 20500, now()),
(3, '대구 삼성 라이온즈 파크', '대구 수성구', 24000, now()),
(4, '사직야구장', '부산 동래구', 23500, now()),
(5, '인천 SSG 랜더스필드', '인천 미추홀구', 23000, now())
ON CONFLICT (stadium_id) DO UPDATE SET name=EXCLUDED.name, location=EXCLUDED.location, capacity=EXCLUDED.capacity;
SELECT setval('game_schema.stadiums_stadium_id_seq', 5);

-- 3-3. 좌석 구역 (잠실 5구역)
INSERT INTO game_schema.seat_sections (section_id, stadium_id, section_name, price, created_at) VALUES
(1, 1, '1루 내야석', 50000, now()),
(2, 1, '3루 내야석', 50000, now()),
(3, 1, '중앙 테이블석', 80000, now()),
(4, 1, '외야석', 20000, now()),
(5, 1, '응원석', 15000, now())
ON CONFLICT (section_id) DO UPDATE SET stadium_id=EXCLUDED.stadium_id, section_name=EXCLUDED.section_name, price=EXCLUDED.price;
SELECT setval('game_schema.seat_sections_section_id_seq', 5);

-- 3-4. 좌석 200석 (구역당 4열 x 10번 = 40석, 5구역)
DELETE FROM ticket_schema.game_seats;
DELETE FROM ticket_schema.seats;
INSERT INTO ticket_schema.seats (stadium_id, section_id, seat_row, seat_number, created_at)
SELECT 1, s.section_id, r.row_name, n.num::text, now()
FROM (VALUES (1),(2),(3),(4),(5)) AS s(section_id)
CROSS JOIN (VALUES ('A'),('B'),('C'),('D')) AS r(row_name)
CROSS JOIN generate_series(1, 10) AS n(num);

-- 3-5. 경기 2개
INSERT INTO game_schema.games (game_id, home_team_name, away_team_name, stadium_id, game_start_time, ticket_open_time, status, created_at) VALUES
(1, 'Doosan Bears', 'LG Twins', 1, '2026-06-01 18:30:00', '2026-05-27 10:00:00', 'TICKET_OPEN', now()),
(2, 'KIA Tigers', 'Samsung Lions', 2, '2026-06-03 18:30:00', '2026-05-28 10:00:00', 'SCHEDULED', now())
ON CONFLICT (game_id) DO UPDATE SET home_team_name=EXCLUDED.home_team_name, away_team_name=EXCLUDED.away_team_name, stadium_id=EXCLUDED.stadium_id, game_start_time=EXCLUDED.game_start_time, ticket_open_time=EXCLUDED.ticket_open_time, status=EXCLUDED.status;
SELECT setval('game_schema.games_game_id_seq', 2);

-- 3-6. 경기1에 좌석 연결 (잠실 200석)
INSERT INTO ticket_schema.game_seats (game_id, seat_id, status, price, updated_at)
SELECT 1, s.seat_id, 'AVAILABLE',
  CASE s.section_id
    WHEN 1 THEN 50000
    WHEN 2 THEN 50000
    WHEN 3 THEN 80000
    WHEN 4 THEN 20000
    WHEN 5 THEN 15000
  END,
  now()
FROM ticket_schema.seats s WHERE s.stadium_id = 1;

-- 3-7. 대기열 정책
INSERT INTO game_schema.waiting_room_policies (game_id, max_enter_per_minute, token_ttl_seconds, enabled, created_at, updated_at) VALUES
(1, 100, 300, true, now(), now()),
(2, 100, 300, true, now(), now())
ON CONFLICT (game_id) DO UPDATE SET max_enter_per_minute=EXCLUDED.max_enter_per_minute, token_ttl_seconds=EXCLUDED.token_ttl_seconds, enabled=EXCLUDED.enabled;

-- 3-8. 주류 메뉴
INSERT INTO order_schema.alcohol_menus (menu_id, name, price, available, created_at) VALUES
(1, '생맥주 500ml', 6000, true, now()),
(2, '캔맥주 355ml', 5000, true, now()),
(3, '하이볼', 8000, true, now()),
(4, '소주', 5000, true, now()),
(5, '순살치킨', 18000, true, now()),
(6, '오징어땅콩', 5000, true, now())
ON CONFLICT (menu_id) DO UPDATE SET name=EXCLUDED.name, price=EXCLUDED.price, available=EXCLUDED.available;
SELECT setval('order_schema.alcohol_menus_menu_id_seq', 6);

-- 3-9. FAQ
INSERT INTO chatbot_schema.faq (faq_id, category, question, answer, enabled, created_at) VALUES
(1, 'RULE', '스트라이크가 뭐야?', '스트라이크는 타자가 치지 않았거나 헛스윙한 공 중 심판이 스트라이크로 판정한 공입니다. 3스트라이크면 삼진 아웃입니다.', true, now()),
(2, 'RULE', '볼이 뭐야?', '볼은 스트라이크 존을 벗어난 투구입니다. 4볼이면 타자가 1루로 출루(볼넷)합니다.', true, now()),
(3, 'TERM', '병살타가 뭐야?', '병살타(더블플레이)는 하나의 타구로 두 명의 주자가 아웃되는 상황입니다.', true, now()),
(4, 'TERM', '홈런이 뭐야?', '홈런은 타자가 친 공이 외야 펜스를 넘어가는 것으로, 타자와 모든 주자가 홈으로 들어옵니다.', true, now()),
(5, 'TICKET', '예매 취소는 어떻게 해?', '현재 예매 취소는 관리자에게 문의해 주세요. 자동 취소 기능은 준비 중입니다.', true, now()),
(6, 'STADIUM', '잠실야구장 주차 가능해?', '잠실야구장은 종합운동장 주차장을 이용할 수 있습니다. 경기일에는 혼잡하므로 대중교통을 권장합니다.', true, now()),
(7, 'ORDER', '주문은 어떻게 해?', '좌석 예매 후 주문 페이지에서 메뉴를 선택하고 수량을 입력한 뒤 주문 생성 버튼을 누르면 됩니다.', true, now())
ON CONFLICT (faq_id) DO UPDATE SET category=EXCLUDED.category, question=EXCLUDED.question, answer=EXCLUDED.answer, enabled=EXCLUDED.enabled;
SELECT setval('chatbot_schema.faq_faq_id_seq', 7);

-- =============================================================================
-- 시퀀스 정리
-- =============================================================================
SELECT setval('auth_schema.users_user_id_seq', GREATEST((SELECT COALESCE(MAX(user_id),1) FROM auth_schema.users), 1));
SELECT setval('ticket_schema.seats_seat_id_seq', GREATEST((SELECT COALESCE(MAX(seat_id),1) FROM ticket_schema.seats), 1));
SELECT setval('ticket_schema.game_seats_game_seat_id_seq', GREATEST((SELECT COALESCE(MAX(game_seat_id),1) FROM ticket_schema.game_seats), 1));

COMMIT;
