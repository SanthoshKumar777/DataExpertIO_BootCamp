--------------------------------------------------
-- create table named players_scd 
--------------------------------------------------
CREATE TABLE players_scd (
	player_name TEXT,
	scoring_class scoring_class,
	is_active BOOLEAN,
	start_season INTEGER,
	end_season INTEGER,
	current_season INTEGER
--	PRIMARY KEY(player_name, current_season)
)

--------------------------------------------------
--  Running historically - inserting scd query based on is_active and scoring_class
--------------------------------------------------

INSERT INTO players_scd 
WITH with_previous AS (
	SELECT 
		player_name,
		scoring_class, 
		is_active,
		current_season,
		LAG(scoring_class, 1) OVER (PARTITION BY player_name ORDER BY current_season) AS previous_scoring_class,
		LAG(is_active, 1) OVER (PARTITION BY player_name ORDER BY current_season) AS previous_is_active
	FROM players
	WHERE current_season<=2021
	),
with_indicators AS (
	SELECT *,
		CASE
			WHEN scoring_class <> previous_scoring_class THEN 1
			WHEN is_active <> previous_is_active THEN 1
			ELSE 0
		END change_indicator
	FROM with_previous
),
with_streaks AS (
	SELECT *,
		SUM(change_indicator) OVER (PARTITION BY player_name ORDER BY current_season ASC) AS streak_indentifer
	FROM with_indicators
)
SELECT 
	player_name, 
	scoring_class,
	is_active,
	MIN(current_season) AS first_season,
	MAX(current_season) AS end_season,
	2021 AS current_season
FROM with_streaks
GROUP BY player_name, streak_indentifer, is_active, scoring_class
ORDER BY player_name

--------------------------------------------------
-- inserting only change in data - but depends_on_past problem 
--------------------------------------------------
CREATE TYPE scd_type AS (
	scoring_class scoring_class,
	is_active boolean,
	start_season INTEGER,
	end_season INTEGER,
	current_season INTEGER
)

WITH last_season_scd AS (
	SELECT * FROM players_scd
	WHERE  current_season = 2021
	AND end_season = 2021
),
historical_scd AS (
	SELECT * FROM players_scd
	WHERE current_season = 2021
	AND end_season < 2021
),
this_season_data AS (
	SELECT * FROM players
	WHERE  current_season = 2022
),
unchanged_records AS (
	SELECT 
		ts.player_name,
		ts.scoring_class,
		ts.is_active,
		ls.start_season ,
		ts.current_season  AS end_season,
		ts.current_season AS current_season
	FROM this_season_data ts
	JOIN last_season_scd ls
	ON ls.player_name = ts.player_name
	WHERE ts.scoring_class = ls.scoring_class
	AND ts.is_active = ls.is_active
),
changed_records AS (
	SELECT 
		ts.player_name,
		UNNEST(ARRAY[
			ROW(
				ls.scoring_class,
				ls.is_active,
				ls.start_season,
				ls.end_season,
				ls.current_season
				)::scd_type, 
			ROW(
				ts.scoring_class,
				ts.is_active,
				ts.current_season,
				ts.current_season,
				ts.current_season
			)::scd_type
		]) AS records
	FROM this_season_data ts
	JOIN last_season_scd ls
	ON ls.player_name = ts.player_name
	WHERE (ts.scoring_class <> ls.scoring_class
	AND ts.is_active <> ls.is_active)
),
unnested_changed_records AS (
	SELECT 
		player_name,
		(records::scd_type).*
	
	FROM changed_records
),
new_records AS (
	SELECT 
		ts.player_name,
		ts.scoring_class,
		ts.is_active,
		ts.current_season  AS start_season,
		ts.current_season  AS end_season,
		ts.current_season AS current_season
	FROM this_season_data ts
	JOIN last_season_scd ls
	ON ls.player_name = ts.player_name
	WHERE ls.player_name IS NULL
)
SELECT * FROM historical_scd
UNION ALL
SELECT * FROM unchanged_records
UNION ALL
SELECT * FROM unnested_changed_records
UNION ALL
SELECT * FROM new_records
--------------------------------------------------
