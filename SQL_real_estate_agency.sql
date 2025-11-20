-- Задача 1: Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ), 
-- Разделим на категории по кол-ву дней существования объявления
category_days AS(
	SELECT *, 
			CASE WHEN days_exposition<=30 AND days_exposition>=1 THEN '1-30 days'
					WHEN days_exposition<=90 AND days_exposition>=31 THEN '31-90 days'
					WHEN days_exposition<=180 AND days_exposition>=91 THEN '91-180 days'
					WHEN days_exposition<=1580 AND days_exposition>=181 THEN '181+ days'
					ELSE 'non category'
			END AS category_days
	FROM real_estate.advertisement
),
--Категория по региону
category_city AS(
	SELECT *, 
			CASE WHEN city = 'Санкт-Петербург' THEN 'Санкт-Петербург' ELSE 'Ленинградская область' END AS region
	FROM real_estate.city 
)
--Основной запрос
SELECT region, 
		category_days , 
		COUNT(id) AS count_advertisement,
		ROUND(AVG(last_price / total_area)::NUMERIC ,2) AS avg_price_one_meter, 
		ROUND(AVG(total_area)::NUMERIC,2) AS avg_total_area,
		ROUND(AVG(last_price)::NUMERIC,2) AS avg_price,
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rooms) AS median_rooms,
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY balcony ) AS median_balcony,
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY floor ) AS median_floor,
		ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY region), 2) AS share_in_region_pct,  -- Доля категории от всех объявлений в этом регионе
		ROUND(AVG(ceiling_height)::NUMERIC,2) AS avg_ceiling_height,  -- Ср высота потолка
		ROUND(AVG(airports_nearest)::NUMERIC,2) AS avg_airports_nearest, -- Ср расстояние до аэропорта
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY parks_around3000) AS median_parks_around, -- Медиана парков
		PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ponds_around3000) AS median_ponds_around, -- Медиана водоемов
		ROUND(100.0 * SUM(CASE WHEN rooms = 0 THEN 1 ELSE 0 END) / COUNT(*)::NUMERIC, 2) AS studios_pct, -- Процент студий
		ROUND(100.0 * SUM(CASE WHEN is_apartment = 1 THEN 1 ELSE 0 END) / COUNT(*)::NUMERIC, 2) AS apartment_pct, -- Процент апартаментов
		ROUND(100.0 * SUM(CASE WHEN open_plan = 1 THEN 1 ELSE 0 END) / COUNT(*)::NUMERIC, 2) AS open_plan_pct -- Процент свободной планировки
FROM real_estate.flats
LEFT JOIN category_days USING(id)
LEFT JOIN category_city USING(city_id )
LEFT JOIN real_estate.type  USING(type_id)
--Выделим только нужные id, тип город и даты с 2015 по 2018 год
WHERE id IN (SELECT * FROM filtered_id) AND (TYPE = 'город') AND (EXTRACT(YEAR FROM first_day_exposition) >= '2015' AND EXTRACT(YEAR FROM first_day_exposition) <= '2018')
GROUP BY region, category_days; 


-- Задача 2: Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
--Сначала добавим день снятия с продажи и применим фильтры:
final_data AS(
	SELECT *, first_day_exposition + (days_exposition || ' days')::INTERVAL AS end_day_exposition
	FROM real_estate.flats
	LEFT JOIN real_estate.advertisement USING(id)
	LEFT JOIN real_estate.type USING(type_id)
	WHERE id IN (SELECT * FROM filtered_id) AND (TYPE = 'город') AND (EXTRACT(YEAR FROM first_day_exposition) >= '2015' AND EXTRACT(YEAR FROM first_day_exposition) <= '2018')
),
--Временной ряд по месяцам количества снятых/выставленных общявлений
new_adv AS (
SELECT
	EXTRACT(MONTH FROM first_day_exposition) AS month_num,   -- Сменили условие группировки на по месяцам
	TO_CHAR(first_day_exposition, 'Month') AS month_name,
	COUNT(*) AS new_adv,
	ROUND(AVG(total_area)::NUMERIC , 2) AS avg_new_total_area,  -- Добавим метрики средняя стоимость за кв метр и средняя площадь квартиры
	ROUND(AVG(last_price / total_area::float)::NUMERIC , 2) AS avg_new_price_meter,
	RANK() OVER (ORDER BY COUNT(*) DESC) AS new_adv_rank, -- Добавили ранги
	ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS new_adv_pct -- Процент опубликованных от общего
FROM final_data
GROUP BY month_num,
		 month_name
),
removed_adv AS (
SELECT
	EXTRACT(MONTH FROM end_day_exposition) AS month_num,
	TO_CHAR(end_day_exposition, 'Month') AS month_name,
	COUNT(*)AS removed_adv,
	ROUND(AVG(total_area)::NUMERIC , 2) AS avg_removed_total_area,   --Добавим метрики средняя стоимость за кв метр и средняя площадь квартиры
	ROUND(AVG(last_price / total_area::float)::NUMERIC , 2) AS avg_removed_price_meter,
	RANK() OVER (ORDER BY COUNT(*) DESC) AS removed_adv_rank, -- Добавили ранги
	ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS removed_adv_pct -- Процент опубликованных от общего
FROM final_data
GROUP BY month_num, 
		 month_name
)
SELECT month_name,
		new_adv,
		removed_adv,
		new_adv_rank,
		removed_adv_rank,
		new_adv_pct,
		removed_adv_pct,
		avg_new_total_area,
		avg_removed_total_area,
		avg_new_price_meter,
		avg_removed_price_meter
FROM new_adv
LEFT JOIN removed_adv USING(month_num, month_name)
ORDER BY month_num;