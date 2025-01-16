--------------------------------------------------
-- inserting data by comparing today with yesteday on users_cummulated
--------------------------------------------------
DO $$ 
DECLARE 
    series_date DATE;
BEGIN
    FOR series_date IN 
        SELECT * 
        FROM generate_series(DATE '2023-01-01', DATE '2023-01-31', INTERVAL '1 day')
    LOOP
        INSERT INTO users_cummulated (
            user_id, 
            dates_active, 
            date
        )
        WITH yesterday AS (
            SELECT 
                user_id,
                dates_active
            FROM users_cummulated 
            WHERE date = series_date - INTERVAL '1 day'
        ),
        today AS (
            SELECT 
                CAST(user_id AS TEXT),
                DATE(event_time) AS date_active
            FROM events 
            WHERE DATE(event_time) = series_date
              AND user_id IS NOT NULL
            GROUP BY user_id, DATE(event_time)
        )
        SELECT 
            COALESCE(t.user_id, y.user_id),
            CASE 
                WHEN y.dates_active IS NULL
                    THEN ARRAY[t.date_active]
                WHEN t.date_active IS NULL
                    THEN y.dates_active
                ELSE y.dates_active || ARRAY[t.date_active]
            END AS dates_active,
            series_date
        FROM today t 
        FULL OUTER JOIN yesterday y 
            ON t.user_id = y.user_id;
    END LOOP;
END $$;



--------------------------------------------------
-- create users_cummulated tabel where they were active
--------------------------------------------------
CREATE TABLE users_cummulated (
	user_id TEXT,
	dates_active DATE[], -- list OF dates IN the past WHERE USER active
	date DATE, -- the CURRENT date FOR the user
	PRIMARY KEY (user_id, date)
)
--------------------------------------------------
-- generate date_list to compress dates_active
--------------------------------------------------
WITH users AS (
	SELECT * FROM users_cummulated
	WHERE date = DATE('2023-01-31')
),
series AS (
	SELECT * FROM generate_series(DATE('2023-01-01'), DATE('2023-01-31'), INTERVAL '1 day') AS series_date
),
place_holder_ints AS (
SELECT
	*,
	CASE 
		WHEN dates_active @> ARRAY[DATE(series_date)]
			THEN CAST(POW(2, 32 - (date - DATE(series_date))) AS BIGINT)
		ELSE 0
	END AS placeholder_int_value
FROM users
CROSS JOIN series
)
SELECT 
	user_id, 
	CAST(CAST(SUM(placeholder_int_value) AS BIGINT) AS BIT(32)), 
	BIT_COUNT(CAST(CAST(SUM(placeholder_int_value) AS BIGINT) AS BIT(32))) AS dim_is_monthly_active,
	CAST('11111110000000000000000000' AS BIT(32)) & 
		CAST(CAST(SUM(placeholder_int_value) AS BIGINT) AS BIT(32)) AS dim_is_weekly_active
FROM place_holder_ints
GROUP BY user_id
--------------------------------------------------
