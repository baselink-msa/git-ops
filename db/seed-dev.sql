-- Dev seed data for Baselink MSA.
-- Password for the dev admin account is: Password123!
--
-- Run inside the EKS cluster or another network path that can reach the private RDS.
-- Example:
--   psql "$DATABASE_URL" -f gitops/db/seed-dev.sql

BEGIN;

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
    'Dev Admin',
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

SELECT setval(
    'auth_schema.users_user_id_seq',
    GREATEST((SELECT COALESCE(MAX(user_id), 1) FROM auth_schema.users), 1)
);

INSERT INTO game_schema.stadiums (
    stadium_id,
    name,
    location,
    capacity,
    created_at
)
VALUES (
    1,
    'Jamsil Baseball Stadium',
    'Seoul',
    25000,
    now()
)
ON CONFLICT (stadium_id) DO UPDATE
SET
    name = EXCLUDED.name,
    location = EXCLUDED.location,
    capacity = EXCLUDED.capacity;

SELECT setval(
    'game_schema.stadiums_stadium_id_seq',
    GREATEST((SELECT COALESCE(MAX(stadium_id), 1) FROM game_schema.stadiums), 1)
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
VALUES (
    1,
    'Doosan Bears',
    'LG Twins',
    1,
    '2026-06-01 18:30:00',
    '2026-05-27 10:00:00',
    'SCHEDULED',
    now()
)
ON CONFLICT (game_id) DO UPDATE
SET
    home_team_name = EXCLUDED.home_team_name,
    away_team_name = EXCLUDED.away_team_name,
    stadium_id = EXCLUDED.stadium_id,
    game_start_time = EXCLUDED.game_start_time,
    ticket_open_time = EXCLUDED.ticket_open_time,
    status = EXCLUDED.status;

SELECT setval(
    'game_schema.games_game_id_seq',
    GREATEST((SELECT COALESCE(MAX(game_id), 1) FROM game_schema.games), 1)
);

INSERT INTO game_schema.seat_sections (
    section_id,
    stadium_id,
    section_name,
    price,
    created_at
)
VALUES (
    1,
    1,
    'First Base A',
    50000,
    now()
)
ON CONFLICT (section_id) DO UPDATE
SET
    stadium_id = EXCLUDED.stadium_id,
    section_name = EXCLUDED.section_name,
    price = EXCLUDED.price;

SELECT setval(
    'game_schema.seat_sections_section_id_seq',
    GREATEST((SELECT COALESCE(MAX(section_id), 1) FROM game_schema.seat_sections), 1)
);

INSERT INTO ticket_schema.seats (
    seat_id,
    stadium_id,
    section_id,
    seat_row,
    seat_number,
    created_at
)
VALUES (
    1,
    1,
    1,
    'A',
    '1',
    now()
)
ON CONFLICT (seat_id) DO UPDATE
SET
    stadium_id = EXCLUDED.stadium_id,
    section_id = EXCLUDED.section_id,
    seat_row = EXCLUDED.seat_row,
    seat_number = EXCLUDED.seat_number;

SELECT setval(
    'ticket_schema.seats_seat_id_seq',
    GREATEST((SELECT COALESCE(MAX(seat_id), 1) FROM ticket_schema.seats), 1)
);

INSERT INTO ticket_schema.game_seats (
    game_seat_id,
    game_id,
    seat_id,
    price,
    status,
    updated_at
)
VALUES (
    1,
    1,
    1,
    50000,
    'AVAILABLE',
    now()
)
ON CONFLICT (game_seat_id) DO UPDATE
SET
    game_id = EXCLUDED.game_id,
    seat_id = EXCLUDED.seat_id,
    price = EXCLUDED.price,
    status = EXCLUDED.status,
    updated_at = now();

SELECT setval(
    'ticket_schema.game_seats_game_seat_id_seq',
    GREATEST((SELECT COALESCE(MAX(game_seat_id), 1) FROM ticket_schema.game_seats), 1)
);

COMMIT;
