-- =============================================================================
-- Baselink dev database bootstrap
--
-- Purpose:
--   Recreate the minimum dev database structure and test data after RDS is
--   recreated. This file is intentionally idempotent: it can be run more than
--   once in the dev environment.
--
-- Dev admin account:
--   email: admin@baselink.dev
--   password: Password123!
--
-- Recommended restore order after terraform apply:
--   1. Create backend-secret.
--   2. Run this SQL against the RDS database.
--   3. Apply or restart backend workloads.
--
-- PowerShell example using an existing psql-inspect pod:
--   Get-Content .\gitops\db\seed-dev.sql |
--     kubectl exec -i -n baselink-dev psql-inspect -- psql -v ON_ERROR_STOP=1
-- =============================================================================

-- BEGIN transaction removed for idempotent execution

-- =============================================================================
-- 1. Schemas
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS auth_schema;
CREATE SCHEMA IF NOT EXISTS game_schema;
CREATE SCHEMA IF NOT EXISTS ticket_schema;
CREATE SCHEMA IF NOT EXISTS order_schema;
CREATE SCHEMA IF NOT EXISTS chatbot_schema;

-- =============================================================================
-- 2. Tables
-- =============================================================================

CREATE TABLE IF NOT EXISTS auth_schema.users (
    user_id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    role VARCHAR(30) NOT NULL,
    status VARCHAR(30) NOT NULL,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS game_schema.stadiums (
    stadium_id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255),
    location VARCHAR(255),
    capacity INTEGER,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS game_schema.games (
    game_id BIGSERIAL PRIMARY KEY,
    home_team_name VARCHAR(255),
    away_team_name VARCHAR(255),
    stadium_id BIGINT REFERENCES game_schema.stadiums(stadium_id),
    game_start_time TIMESTAMP,
    ticket_open_time TIMESTAMP,
    status VARCHAR(30),
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS game_schema.seat_sections (
    section_id BIGSERIAL PRIMARY KEY,
    stadium_id BIGINT REFERENCES game_schema.stadiums(stadium_id),
    section_name VARCHAR(255),
    price INTEGER,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ticket_schema.seats (
    seat_id BIGSERIAL PRIMARY KEY,
    stadium_id BIGINT REFERENCES game_schema.stadiums(stadium_id),
    section_id BIGINT REFERENCES game_schema.seat_sections(section_id),
    seat_row VARCHAR(255),
    seat_number VARCHAR(255),
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ticket_schema.game_seats (
    game_seat_id BIGSERIAL PRIMARY KEY,
    game_id BIGINT REFERENCES game_schema.games(game_id) ON DELETE CASCADE,
    seat_id BIGINT REFERENCES ticket_schema.seats(seat_id),
    status VARCHAR(30),
    price NUMERIC(12, 2),
    updated_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ticket_schema.reservations (
    reservation_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    game_id BIGINT NOT NULL,
    seat_id BIGINT NOT NULL,
    status VARCHAR(30) NOT NULL,
    lock_id VARCHAR(255),
    idempotency_key VARCHAR(255),
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ticket_schema.waiting_room_policies (
    policy_id BIGSERIAL PRIMARY KEY,
    game_id BIGINT UNIQUE,
    max_enter_per_minute INTEGER,
    token_ttl_seconds INTEGER,
    enabled BOOLEAN,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

-- game_id unique constraint 보장 (JPA가 먼저 만들었을 경우 누락될 수 있음)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'waiting_room_policies_game_id_key') THEN
    ALTER TABLE ticket_schema.waiting_room_policies ADD CONSTRAINT waiting_room_policies_game_id_key UNIQUE (game_id);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS order_schema.alcohol_menus (
    menu_id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255),
    price INTEGER,
    available BOOLEAN,
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

CREATE TABLE IF NOT EXISTS chatbot_schema.faq (
    faq_id BIGSERIAL PRIMARY KEY,
    category VARCHAR(255),
    question VARCHAR(255),
    answer VARCHAR(255),
    enabled BOOLEAN,
    created_at TIMESTAMP DEFAULT now()
);

-- Keep dev check constraints aligned with current Java enums.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.table_constraints
        WHERE table_schema = 'ticket_schema'
          AND table_name = 'game_seats'
          AND constraint_name = 'game_seats_status_check'
    ) THEN
        ALTER TABLE ticket_schema.game_seats DROP CONSTRAINT game_seats_status_check;
    END IF;

    ALTER TABLE ticket_schema.game_seats
        ADD CONSTRAINT game_seats_status_check
        CHECK (status IN ('AVAILABLE', 'SOLD', 'BLOCKED', 'LOCKED'));
EXCEPTION
    WHEN duplicate_object THEN
        NULL;
END $$;

-- =============================================================================
-- 3. Seed data
-- =============================================================================

INSERT INTO auth_schema.users (
    email,
    password_hash,
    name,
    role,
    status,
    created_at
)
VALUES (
    'admin@baselink.dev',
    '$2a$10$PKjB55l3JArzLe6eKh71UOpcI9/kwQ4cfvjKkG65PahDK9vbXBqPC',
    '개발 관리자',
    'ADMIN',
    'ACTIVE',
    now()
)
ON CONFLICT (email) DO UPDATE
SET
    password_hash = EXCLUDED.password_hash,
    name = EXCLUDED.name,
    role = EXCLUDED.role,
    status = EXCLUDED.status;

INSERT INTO game_schema.stadiums (
    stadium_id,
    name,
    location,
    capacity,
    created_at
)
VALUES
    (1, '잠실야구장', '서울특별시 송파구', 25000, now()),
    (2, '광주-KIA 챔피언스 필드', '광주광역시 북구', 20500, now()),
    (3, '대구 삼성 라이온즈 파크', '대구광역시 수성구', 24000, now()),
    (4, '사직야구장', '부산광역시 동래구', 23500, now()),
    (5, '인천 SSG 랜더스필드', '인천광역시 미추홀구', 23000, now())
ON CONFLICT (stadium_id) DO UPDATE
SET
    name = EXCLUDED.name,
    location = EXCLUDED.location,
    capacity = EXCLUDED.capacity;

SELECT setval('game_schema.stadiums_stadium_id_seq', GREATEST((SELECT MAX(stadium_id) FROM game_schema.stadiums), 1));

UPDATE game_schema.seat_sections
SET section_name = CASE section_name
    WHEN 'First Base Infield' THEN '1루 내야석'
    WHEN 'Third Base Infield' THEN '3루 내야석'
    WHEN 'Central Table Seat' THEN '중앙 테이블석'
    WHEN 'Outfield' THEN '외야석'
    WHEN 'Cheering Seat' THEN '응원석'
    ELSE section_name
END;

UPDATE game_schema.seat_sections
SET section_name = CASE ((section_id - 1) % 5)
    WHEN 0 THEN '1루 내야석'
    WHEN 1 THEN '3루 내야석'
    WHEN 2 THEN '중앙 테이블석'
    WHEN 3 THEN '외야석'
    WHEN 4 THEN '응원석'
    ELSE section_name
END
WHERE section_name IN ('1? ???', '3? ???', '?? ????', '???');

INSERT INTO game_schema.seat_sections (
    stadium_id,
    section_name,
    price,
    created_at
)
SELECT s.stadium_id, sec.section_name, sec.price, now()
FROM game_schema.stadiums s
CROSS JOIN (
    VALUES
        ('1루 내야석', 50000),
        ('3루 내야석', 50000),
        ('중앙 테이블석', 80000),
        ('외야석', 20000),
        ('응원석', 15000)
) AS sec(section_name, price)
WHERE NOT EXISTS (
    SELECT 1
    FROM game_schema.seat_sections existing
    WHERE existing.stadium_id = s.stadium_id
      AND existing.section_name = sec.section_name
);

INSERT INTO ticket_schema.seats (
    stadium_id,
    section_id,
    seat_row,
    seat_number,
    created_at
)
SELECT ss.stadium_id, ss.section_id, row_data.seat_row, num_data.seat_number::text, now()
FROM game_schema.seat_sections ss
CROSS JOIN (VALUES ('A'), ('B'), ('C'), ('D')) AS row_data(seat_row)
CROSS JOIN generate_series(1, 10) AS num_data(seat_number)
WHERE NOT EXISTS (
    SELECT 1
    FROM ticket_schema.seats existing
    WHERE existing.stadium_id = ss.stadium_id
      AND existing.section_id = ss.section_id
      AND existing.seat_row = row_data.seat_row
      AND existing.seat_number = num_data.seat_number::text
);

INSERT INTO game_schema.games (
    game_id,
    home_team_name,
    away_team_name,
    stadium_id,
    game_start_time,
    ticket_open_time,
    status,
    created_at
)
VALUES
    (1, '두산 베어스', 'LG 트윈스', 1, '2026-06-01 18:30:00', '2026-05-27 10:00:00', 'TICKET_OPEN', now()),
    (2, 'KIA 타이거즈', '삼성 라이온즈', 2, '2026-06-03 18:30:00', '2026-05-28 10:00:00', 'SCHEDULED', now())
ON CONFLICT (game_id) DO UPDATE
SET
    home_team_name = EXCLUDED.home_team_name,
    away_team_name = EXCLUDED.away_team_name,
    stadium_id = EXCLUDED.stadium_id,
    game_start_time = EXCLUDED.game_start_time,
    ticket_open_time = EXCLUDED.ticket_open_time,
    status = EXCLUDED.status;

SELECT setval('game_schema.games_game_id_seq', GREATEST((SELECT MAX(game_id) FROM game_schema.games), 1));

INSERT INTO ticket_schema.game_seats (
    game_id,
    seat_id,
    status,
    price,
    updated_at
)
SELECT g.game_id, s.seat_id, 'AVAILABLE', COALESCE(ss.price, 30000), now()
FROM game_schema.games g
JOIN ticket_schema.seats s ON s.stadium_id = g.stadium_id
LEFT JOIN game_schema.seat_sections ss ON ss.section_id = s.section_id
WHERE NOT EXISTS (
    SELECT 1
    FROM ticket_schema.game_seats existing
    WHERE existing.game_id = g.game_id
      AND existing.seat_id = s.seat_id
);

INSERT INTO ticket_schema.waiting_room_policies (
    game_id,
    max_enter_per_minute,
    token_ttl_seconds,
    enabled,
    created_at,
    updated_at
)
VALUES
    (1, 100, 300, true, now(), now()),
    (2, 100, 300, true, now(), now())
ON CONFLICT (game_id) DO UPDATE
SET
    max_enter_per_minute = EXCLUDED.max_enter_per_minute,
    token_ttl_seconds = EXCLUDED.token_ttl_seconds,
    enabled = EXCLUDED.enabled,
    updated_at = now();

INSERT INTO order_schema.alcohol_menus (
    menu_id,
    name,
    price,
    available,
    created_at
)
VALUES
    (1, '생맥주 500ml', 6000, true, now()),
    (2, '캔맥주 355ml', 5000, true, now()),
    (3, '하이볼', 8000, true, now()),
    (4, '소주', 5000, true, now()),
    (5, '치킨 바스켓', 18000, true, now()),
    (6, '나초', 5000, true, now())
ON CONFLICT (menu_id) DO UPDATE
SET
    name = EXCLUDED.name,
    price = EXCLUDED.price,
    available = EXCLUDED.available;

SELECT setval('order_schema.alcohol_menus_menu_id_seq', GREATEST((SELECT MAX(menu_id) FROM order_schema.alcohol_menus), 1));

INSERT INTO chatbot_schema.faq (
    faq_id,
    category,
    question,
    answer,
    enabled,
    created_at
)
VALUES
    (1, 'RULE', '스트라이크가 뭐예요?', '타자가 헛스윙하거나, 스트라이크 존에 들어온 공을 치지 않거나, 2스트라이크 이전에 파울을 치면 스트라이크가 됩니다.', true, now()),
    (2, 'RULE', '볼이 뭐예요?', '스트라이크 존을 벗어난 공에 타자가 스윙하지 않으면 볼이 됩니다. 볼 4개가 되면 1루로 진루합니다.', true, now()),
    (3, 'TERM', '병살타가 뭐예요?', '수비팀이 하나의 연속된 플레이에서 아웃카운트 2개를 잡는 상황입니다.', true, now()),
    (4, 'TERM', '홈런이 뭐예요?', '타자가 친 공으로 모든 베이스를 돌아 득점하는 안타입니다.', true, now()),
    (5, 'TICKET', '예매를 취소하려면 어떻게 하나요?', '개발 환경에서는 관리자에게 문의해 예매 취소를 진행해 주세요.', true, now()),
    (6, 'STADIUM', '잠실야구장 주차가 가능한가요?', '경기일에는 주차 공간이 부족할 수 있어 대중교통 이용을 권장합니다.', true, now()),
    (7, 'ORDER', '음식이나 주류는 어떻게 주문하나요?', '좌석 선택 후 주문 페이지에서 메뉴를 고르고 주문을 제출하면 됩니다.', true, now())
ON CONFLICT (faq_id) DO UPDATE
SET
    category = EXCLUDED.category,
    question = EXCLUDED.question,
    answer = EXCLUDED.answer,
    enabled = EXCLUDED.enabled;

SELECT setval('chatbot_schema.faq_faq_id_seq', GREATEST((SELECT MAX(faq_id) FROM chatbot_schema.faq), 1));
SELECT setval('auth_schema.users_user_id_seq', GREATEST((SELECT MAX(user_id) FROM auth_schema.users), 1));
SELECT setval('ticket_schema.seats_seat_id_seq', GREATEST((SELECT MAX(seat_id) FROM ticket_schema.seats), 1));
SELECT setval('ticket_schema.game_seats_game_seat_id_seq', GREATEST((SELECT MAX(game_seat_id) FROM ticket_schema.game_seats), 1));

-- COMMIT removed
