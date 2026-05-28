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
