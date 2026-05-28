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

INSERT INTO game_schema.stadiums (
    stadium_id,
    name,
    location,
    capacity,
    created_at
)
VALUES
    (1, 'Jamsil Baseball Stadium', 'Seoul Songpa-gu', 25000, now()),
    (2, 'Gwangju Champions Field', 'Gwangju Buk-gu', 20500, now()),
    (3, 'Daegu Samsung Lions Park', 'Daegu Suseong-gu', 24000, now()),
    (4, 'Sajik Baseball Stadium', 'Busan Dongnae-gu', 23500, now()),
    (5, 'Incheon SSG Landers Field', 'Incheon Michuhol-gu', 23000, now())
ON CONFLICT (stadium_id) DO UPDATE
SET
    name = EXCLUDED.name,
    location = EXCLUDED.location,
    capacity = EXCLUDED.capacity;

SELECT setval('game_schema.stadiums_stadium_id_seq', GREATEST((SELECT MAX(stadium_id) FROM game_schema.stadiums), 1));

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
        ('First Base Infield', 50000),
        ('Third Base Infield', 50000),
        ('Central Table Seat', 80000),
        ('Outfield', 20000),
        ('Cheering Seat', 15000)
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
    (1, 'Doosan Bears', 'LG Twins', 1, '2026-06-01 18:30:00', '2026-05-27 10:00:00', 'TICKET_OPEN', now()),
    (2, 'KIA Tigers', 'Samsung Lions', 2, '2026-06-03 18:30:00', '2026-05-28 10:00:00', 'SCHEDULED', now())
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
    (1, 'Draft Beer 500ml', 6000, true, now()),
    (2, 'Can Beer 355ml', 5000, true, now()),
    (3, 'Highball', 8000, true, now()),
    (4, 'Soju', 5000, true, now()),
    (5, 'Chicken Basket', 18000, true, now()),
    (6, 'Nachos', 5000, true, now())
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
    (1, 'RULE', 'What is a strike?', 'A strike is called when the batter swings and misses, does not swing at a pitch in the strike zone, or fouls the ball before two strikes.', true, now()),
    (2, 'RULE', 'What is a ball?', 'A ball is a pitch outside the strike zone that the batter does not swing at. Four balls award first base.', true, now()),
    (3, 'TERM', 'What is a double play?', 'A double play is a defensive play that records two outs during one continuous play.', true, now()),
    (4, 'TERM', 'What is a home run?', 'A home run is a hit that allows the batter to circle all bases and score.', true, now()),
    (5, 'TICKET', 'How can I cancel a ticket?', 'For now, please contact an administrator for ticket cancellation in the dev environment.', true, now()),
    (6, 'STADIUM', 'Is parking available at Jamsil Baseball Stadium?', 'Parking may be limited on game days. Public transportation is recommended.', true, now()),
    (7, 'ORDER', 'How do I order food or drinks?', 'After selecting a seat, open the order page, choose menu items, and submit the order.', true, now())
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
