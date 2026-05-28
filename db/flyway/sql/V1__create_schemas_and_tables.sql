CREATE SCHEMA IF NOT EXISTS auth_schema;
CREATE SCHEMA IF NOT EXISTS game_schema;
CREATE SCHEMA IF NOT EXISTS ticket_schema;
CREATE SCHEMA IF NOT EXISTS order_schema;
CREATE SCHEMA IF NOT EXISTS chatbot_schema;

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
