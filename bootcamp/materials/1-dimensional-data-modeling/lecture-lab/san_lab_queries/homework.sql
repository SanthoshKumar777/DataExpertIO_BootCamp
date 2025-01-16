--------------------------------------------------
-- create struct type named films_type 
--------------------------------------------------
CREATE TYPE films_type AS (
	film TEXT,
	votes INTEGER,
	rating REAL,
	filmid TEXT
)

CREATE TYPE quality_class_type AS ENUM('star', 'good', 'average', 'bad') 
--------------------------------------------------
-- create table named `actor`
--------------------------------------------------
CREATE TABLE actors (
	actor TEXT,
	actorid TEXT,
	films films_type[],
	quality_class quality_class_type,
	is_active BOOLEAN,
	YEAR INTEGER,
	PRIMARY KEY (actorid, year)
)

--------------------------------------------------
-- cummulative table generation
--------------------------------------------------
DO $$
DECLARE 
	ref_year INTEGER;
BEGIN
	FOR ref_year IN SELECT * FROM generate_series(1970, 2021)
	LOOP
	INSERT INTO actors (
	WITH prev_year AS (
		SELECT * FROM actors WHERE year=ref_year-1
	),
	current_year AS (
		SELECT 
			actorid,
			actor,
			YEAR,
			AVG(rating) AS avg_ratings,
			TRUE as is_active,
			array_agg(ROW(film,votes,rating,filmid)::films_type) AS film_records
		FROM actor_films WHERE year=ref_year
		GROUP BY actorid, actor, year
	)
	SELECT 
		COALESCE(c.actor, p.actor) AS actor,
		COALESCE(c.actorid, p.actorid) AS actorid,
		CASE
			WHEN p.films IS NULL 
				THEN film_records
			WHEN film_records IS NOT NULL
				THEN p.films || film_records
			ELSE
				p.films
		END AS films,
		CASE
			WHEN c.avg_ratings IS NOT NULL
			 THEN
			 	CASE
				 	WHEN c.avg_ratings > 8 THEN 'star'
				 	WHEN c.avg_ratings > 7 AND c.avg_ratings <= 8 THEN 'good'
				 	WHEN c.avg_ratings > 6 AND c.avg_ratings <= 7 THEN 'average'
				 	ELSE 'bad'
				 	END::quality_class_type
			ELSE quality_class
		END AS quality_class,
		c.is_active IS NOT NULL AS is_active,
		COALESCE(c.YEAR, p.YEAR+1) AS year
	FROM current_year AS c
	FULL OUTER JOIN prev_year AS p
	ON p.actorid=c.actorid
	);
	END LOOP;
END $$
	

--------------------------------------------------
-- **DDL for `actors_history_scd` table:** 
-------------------------------------------------
CREATE TABLE actors_history_scd (
	actorid TEXT,
	actor TEXT,
	quality_class quality_class_type,
	is_active BOOLEAN,
	start_date INTEGER,
	end_date INTEGER,
	YEAR INTEGER
)
--------------------------------------------------
-- Backfill query for actors_history_scd:
--------------------------------------------------
INSERT INTO actors_history_scd
WITH with_previous AS (
	SELECT 
		actorid,
		actor,
		quality_class,
		is_active,
		LAG(quality_class, 1) OVER (PARTITION BY actorid ORDER BY year) AS previous_quality_class,
		LAG(is_active, 1) OVER (PARTITION BY actorid ORDER BY year) AS previous_is_active,
		YEAR
	FROM actors 
	WHERE YEAR<=2019
),
with_indicators AS (
	SELECT *,
		CASE
			WHEN quality_class <> previous_quality_class OR is_active <> previous_is_active THEN 1
			ELSE 0
		END AS change_indicator
	FROM with_previous
),
with_streaks AS (
	SELECT 
		*,
		SUM(change_indicator) OVER(PARTITION BY actorid ORDER BY year) AS streaks
	FROM with_indicators
)
SELECT
	actorid,
	actor,
	quality_class,
	is_active,
	MIN(YEAR) AS start_date,
	MAX(YEAR) AS end_date,
	2019 AS current_date
FROM with_streaks
GROUP BY actorid, actor, quality_class, is_active, streaks
ORDER BY actorid, actor

--------------------------------------------------
-- Incremental query for actors_history_scd
--------------------------------------------------
CREATE TYPE actor_scd_type AS (
	quality_class quality_class_type,
	is_active BOOLEAN, 
	start_date INTEGER,
	end_date INTEGER,
	YEAR INTEGER
)

INSERT INTO actors_history_scd 
WITH last_year_scd AS (
	SELECT * FROM actors_history_scd
	WHERE YEAR=2019
),
historical_scd AS (
	SELECT * FROM actors_history_scd
	WHERE YEAR<2019
),
current_year_scd AS (
	SELECT * FROM actors
	WHERE YEAR=2020
),
unchanged_records AS (
	SELECT 
		cys.actorid,
		cys.actor,
		cys.quality_class,
		cys.is_active,
		lys.start_date,
		cys.YEAR AS end_date,
		cys.YEAR AS YEAR
	FROM current_year_scd AS cys
	INNER JOIN last_year_scd AS lys
	ON cys.actorid=lys.actorid
	AND cys.is_active=lys.is_active
	AND cys.quality_class=lys.quality_class
),
changed_records AS (
	SELECT
		cys.actorid,
		cys.actor,
		UNNEST(
		ARRAY[ROW(
			lys.quality_class,
			lys.is_active,
			lys.start_date,
			lys.end_date,
			lys.YEAR
		)::actor_scd_type, 
		ROW(
			cys.quality_class,
			cys.is_active,
			cys.YEAR,
			cys.YEAR,
			cys.YEAR
		)::actor_scd_type
		]) AS changed_records_data
	FROM current_year_scd AS cys
	INNER JOIN last_year_scd AS lys
	ON cys.actorid=lys.actorid
	AND (cys.is_active<>lys.is_active
	OR cys.quality_class<>lys.quality_class)
),
unnested_change_records AS (
	SELECT 
		actorid,
		actor,
		(changed_records_data::actor_scd_type).*
	FROM changed_records
),
new_records AS (
	SELECT
		cys.actorid,
		cys.actor,
		cys.quality_class,
		cys.is_active,
		cys.YEAR,
		cys.YEAR,
		cys.YEAR
	FROM current_year_scd AS cys
	LEFT JOIN last_year_scd AS lys
	ON cys.actorid=lys.actorid
	WHERE lys.actorid IS NULL 
)
SELECT * FROM historical_scd
UNION ALL
SELECT * FROM unchanged_records
UNION ALL
SELECT * FROM unnested_change_records
UNION ALL
SELECT * FROM new_records

