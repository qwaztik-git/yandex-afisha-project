/* 1.АНАЛИЗ КЛЮЧЕЙ В ТАБЛИЦАХ
purchases (Заказы)
	Первичный ключ: order_id (уникально идентифицирует каждый заказ).
	
	Внешний ключ: event_id указывает на таблицу events(event_id).

events (Мероприятия)
	Первичный ключ: event_id (уникально идентифицирует каждое событие).
	Внешние ключи:
	
		city_id указывает на таблицу city(city_id).
		
		venue_id указывает на таблицу venues(venue_id).
		
venues (Площадки)
	Первичный ключ: venue_id (уникально идентифицирует площадку).
	
	Внешние ключи: Нет.
	
city (Города)
	Первичный ключ: city_id (уникально идентифицирует город).
	
	Внешний ключ: region_id указывает на таблицу regions(region_id).
	
regions (Регионы)
	Первичный ключ: region_id (уникально идентифицирует регион).
	
	Внешние ключи: Нет.
	
2.АНАЛИЗ ТИПОВ СВЯЗИ МЕЖДУ ТАБЛИЦАМИ

regions → city (Один ко многим)  В одном регионе (regions) может находиться много городов (city), но конкретный город относится строго к одному региону.

city → events (Один ко многим) В одном городе может проходить множество мероприятий, но конкретное мероприятие привязано к одному городу.

venues → events (Один ко многим) На одной площадке (venues) может проводиться множество разных мероприятий в разное время, но у конкретного мероприятия указана одна основная площадка.

events → purchases (Один ко многим) На одно и то же мероприятие (events) может быть оформлено множество разных заказов билетов (purchases),
но одна запись заказа относится строго к конкретному мероприятию.*/

/*Проверка объёма данных (Количество строк)*/

SELECT 'purchases' AS table_name, COUNT(*) AS row_count FROM afisha.purchases
UNION ALL
SELECT 'events', COUNT(*) FROM afisha.events
UNION ALL
SELECT 'venues', COUNT(*) FROM afisha.venues
UNION ALL
SELECT 'city', COUNT(*) FROM afisha.city
UNION ALL
SELECT 'regions', COUNT(*) FROM afisha.regions;

/*Анализ полноты данных и пропусков (Качество данных)
 * Для таблицы заказов (purchases):*/

SELECT 
    MIN(created_dt_msk) AS first_order_date,
    MAX(created_dt_msk) AS last_order_date,
    COUNT(*) - COUNT(order_id) AS missing_order_ids,
    COUNT(*) - COUNT(event_id) AS missing_event_ids,
    COUNT(*) - COUNT(revenue) AS missing_revenue
FROM afisha.purchases;

/*Для таблицы мероприятий (events):*/

SELECT 
    COUNT(*) - COUNT(city_id) AS events_without_city,
    COUNT(*) - COUNT(venue_id) AS events_without_venue,
    COUNT(DISTINCT event_type_main) AS unique_event_types
FROM afisha.events;

/*Быстрый просмотр первых строк*/

SELECT * FROM afisha.purchases LIMIT 5;

/*.Проверка уникальности первичных ключей*/

SELECT 
    (SELECT COUNT(order_id) - COUNT(DISTINCT order_id) FROM afisha.purchases) AS purchases_pk_duplicates,
    (SELECT COUNT(event_id) - COUNT(DISTINCT event_id) FROM afisha.events) AS events_pk_duplicates,
    (SELECT COUNT(venue_id) - COUNT(DISTINCT venue_id) FROM afisha.venues) AS venues_pk_duplicates,
    (SELECT COUNT(city_id) - COUNT(DISTINCT city_id) FROM afisha.city) AS city_pk_duplicates,
    (SELECT COUNT(region_id) - COUNT(DISTINCT region_id) FROM afisha.regions) AS regions_pk_duplicates;

/*Скрытые пропуски и пустые строки*/

SELECT 
    COUNT(*) FILTER (WHERE device_type_canonical IS NULL OR TRIM(device_type_canonical) IN ('', 'null', 'none')) AS bad_device_types,
    COUNT(*) FILTER (WHERE currency_code IS NULL OR TRIM(currency_code) IN ('', 'null', 'none')) AS bad_currency_codes,
    COUNT(*) FILTER (WHERE service_name IS NULL OR TRIM(service_name) IN ('', 'null', 'none')) AS bad_service_names
FROM afisha.purchases;

/*Проверка категориальных данных на корректность и опечатки*/

SELECT device_type_canonical, currency_code, COUNT(*) AS count
FROM afisha.purchases
GROUP BY device_type_canonical, currency_code
ORDER BY count DESC;

/*Проверка городов и регионов на аномалии длины и дубликаты:*/

SELECT 'Города с лишними пробелами' AS check_type, COUNT(*) AS count
FROM afisha.city 
WHERE city_name != TRIM(city_name) OR LENGTH(city_name) < 2

UNION ALL

SELECT 'Регионы с лишними пробелами', COUNT(*) 
FROM afisha.regions 
WHERE region_name != TRIM(region_name) OR LENGTH(region_name) < 2;

/*Запрос для проверки типов устройств и валют*/

SELECT device_type_canonical, currency_code, COUNT(*) AS order_count
FROM afisha.purchases
GROUP BY device_type_canonical, currency_code
ORDER BY order_count DESC;

/* мини-вывод: 
 * 1. в названиях всех 353 городов и 81 региона нет скрытых дефектов, опечаток, лишних пробелов в начале или конце строк, а также подозрительно коротких наименований.
 * 2. В полях устройств и валют полностью отсутствует проблема «разного регистра» (нет дублирования вида RUB/rub или Mobile/mobile). Все данные приведены к единому стандарту.
 * 3.Состав устройств и валют:
 * 		Типы устройств: Выделено 5  типов: mobile (абсолютный лидер), desktop, tablet, tv и единичные неопределенные other
		Валюты: Платформа работает в двух валютах — российских рублях (rub) и казахстанских тенге (kzt). 
		Присутствие тенге — это важнейший инсайт для будущих аналитических запросов. Так как у нас есть продажи в разных валютах (rub и kzt), 
		мы не можем просто суммировать столбец total или revenue напрямую во всей таблице, иначе мы сложим рубли с тенге.
	    Для корректного подсчета общей выручки нам понадобится либо конвертация по курсу, либо обязательная фильтрация/группировка по полю currency_code.*/

/*3. РАСПРЕДЕЛЕНИЕ ЗАКАЗОВ ПО ОСНОВНЫМ КАТЕГОРИЯМ*/

/*Распределение заказов по типам устройств и валютам*/
 
SELECT 
    device_type_canonical AS device_type,
    currency_code,
    COUNT(*) AS orders_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM afisha.purchases), 2) AS orders_percentage,
    ROUND(SUM(total)::numeric, 2) AS total_turnover
FROM afisha.purchases
GROUP BY device_type_canonical, currency_code
ORDER BY orders_count DESC;

/*Распределение заказов по типам мероприятий (event_type_main)*/

SELECT 
    e.event_type_main AS event_type,
    COUNT(p.order_id) AS orders_count,
    ROUND(100.0 * COUNT(p.order_id) / (SELECT COUNT(*) FROM afisha.purchases), 2) AS orders_percentage
FROM afisha.purchases p
JOIN afisha.events e ON p.event_id = e.event_id
GROUP BY e.event_type_main
ORDER BY orders_count DESC;

/*Распределение заказов по возрастным ограничениям (age_limit)*/

SELECT 
    age_limit,
    COUNT(*) AS orders_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM afisha.purchases), 2) AS orders_percentage
FROM afisha.purchases
GROUP BY age_limit
ORDER BY age_limit;

/*мини-выводы
Распределение по устройствам и валютам: тотальное доминирование мобильных рублёвых транзакций.
	
	Абсолютный лидер: Комбинация mobile + rub занимает 78.42% от всех заказов на платформе (229 021 транзакция).

 	Каналы продаж: В совокупности покупки со смартфонов и планшетов (mobile + tablet) составляют более 80% от общего объёма. Компьютеры (desktop) удерживают стабильные ~20% рынка.

 	Экстремально малые категории: Устройства категорий tv (3 заказа) и other (2 заказа) практически не генерируют трафик и выручку. 
 	Для будущих отчётов их можно смело объединять с категорией tablet или отбрасывать как статистический шум.

	Валютный барьер: Заказы в тенге (kzt) составляют всего ~1.73% от общего количества транзакций, 
	однако средний чек в тенге визуально значительно выше из-за разницы курсов валют, что подтверждает необходимость строго раздельного подсчёта выручки.

Структура мероприятий: концерты и театр как главные локомотивы

	Ядро продаж: Концерты — самая популярная категория, генерирующая 39.60% всех заказов (115 634).
	на втором месте расположился театр с долей 23.20%. Вместе они обеспечивают почти 2/3 всех продаж на платформе.

	Серые зоны: Категория другое занимает внушительные 22.64%. Это говорит о том, что значительная часть мероприятий не имеет чёткой классификации.

	Категории с небольшим объёмом данных: Самыми малочисленными сегментами оказались сезонные ёлки (0.69%) и фильмы (всего 0.08%, 238
	заказов). Платформа явно не ориентирована на кинопрокат — скорее всего, это единичные фестивальные или специальные показы.

Возрастные ограничения: сбалансированная аудитория
	
	В отличие от резких диспропорций в устройствах и типах контента, распределение по возрастам выглядит относительно равномерным.

	Самой крупной категорией являются мероприятия с маркировкой 16+ (27.01%), что указывает на преобладание подростковой и взрослой аудитории.

	Мероприятия для самой младшей аудитории (0+ и 6+) в сумме занимают около 39%, формируя мощный семейный и детский сегмент платформы.

	Категория строгого совершеннолетия 18+ является самой малочисленной среди возрастов (12.39%), но всё же имеет весомый объём данных (36 175 заказов).*/

/*3. ВОЗМОЖНЫЕ АНОМАЛИИ ИЛИ НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ В ДАННЫХ.
	Расчёт базовых статистических метрик выручки*/

SELECT 
    currency_code,
    COUNT(*) AS total_orders,
    MIN(revenue) AS min_revenue,
    MAX(revenue) AS max_revenue,
    ROUND(AVG(revenue)::numeric, 2) AS avg_revenue,
    MIN(total) AS min_total,
    MAX(total) AS max_total,
    ROUND(AVG(total)::numeric, 2) AS avg_total
FROM afisha.purchases
GROUP BY currency_code;

/*Поиск заказов с нулевой или аномально низкой стоимостью*/

SELECT 
    currency_code,
    COUNT(*) FILTER (WHERE total <= 0) AS zero_or_negative_total,
    COUNT(*) FILTER (WHERE revenue <= 0) AS zero_or_negative_revenue,
    COUNT(*) FILTER (WHERE total > 0 AND revenue = 0) AS zero_revenue_with_positive_total
FROM afisha.purchases
GROUP BY currency_code;

/* Анализ экстремальных выбросов (Топ-5 самых дорогих заказов)
 * 		для рублей:*/

SELECT order_id, tickets_count, revenue, total, device_type_canonical, service_name
FROM afisha.purchases
WHERE currency_code = 'rub'
ORDER BY total DESC
LIMIT 5;

		/*для тенге:*/

SELECT order_id, tickets_count, revenue, total, device_type_canonical, service_name
FROM afisha.purchases
WHERE currency_code = 'kzt'
ORDER BY total DESC
LIMIT 5;

/*мини-вывод
 * Отрицательные значени:
 * 	 	Проблема: Для валюты rub минимальная выручка (revenue) составляет -90.76, а минимальный оборот (total) равен -358.85.
 * 		Причина: Появление отрицательных сумм в коммерческих базах данных обычно связано с оформлением возвратов билетов или отменой заказов.
 * 		Решение?: При подсчёте валовой выручки эти строки будут уменьшать итоговую сумму (что правильно для чистых продаж).
 * 		Однако, если задача состоит в анализе только успешных транзакций или среднего чека покупки, эти строки необходимо будет отфильтровать условием WHERE total > 0.
 * 
 * Нулевые и пропущенные финансовые значения:
 * 		Масштаб: В рублёвых транзакциях обнаружено 6128 строк с нулевым или отрицательным оборотом (total) и 6147 строк с нулевой/отрицательной выручкой сервиса.
 * 		В тенге таких операций всего 6.
 * 		Специфика оператора: Обнаружено 19 заказов в рублях, где клиент заплатил реальные деньги (total > 0), но сервисная выручка платформы составила 
 * 		ровно 0. Это может указывать на промо-акции (продажа билетов без комиссии сервиса) или техническую особенность интеграции с конкретным билетным оператором.
 * 
 * Экстремальные выбросы и повторяющиеся крупные заказы:
 * 	Анализ Топ-5 самых дорогих заказов выявил интересную закономерность:
 * 		Для рублей (rub): Три самые дорогие транзакции имеют абсолютно идентичную структуру: tickets_count = 5, revenue = 81 174.54, total = 811 
 * 		745.40. Все они оформлены через мобильное приложение билетного оператора «Облачко».
 * 		Для тенге (kzt): Три лидирующих заказа также идентичны: tickets_count = 6, revenue = 20 676.39, total = 344 606.50.
 * Вывод по выбросам: Тот факт, что максимальные суммы повторяются до копейки на разных идентификаторах заказов (order_id), 
 * исключает случайный технический сбой ввода (например, если бы пользователь случайно нажал лишний ноль). 
 * Скорее всего, это корпоративные или групповые закупки, которые происходили в рамках одного ценового тарифа. Это реальные валидные данные, но они сильно смещают средний
чек вверх, поэтому при анализе типичного поведения пользователей лучше ориентироваться на медиану, а не на среднее арифметическое.*/

/*4.Период, за который представлены данные.*/

/*На этапе предварительного анализа объема данных мы определили, что транзакции в таблице purchases охватывают ровно 5 месяцев 2024 года: с 1 июня по 31 октября включительно.*/

/*проверим помесячную динамику продаж, чтобы точно оценить влияние сезонных факторов.*/

SELECT 
    TO_CHAR(created_dt_msk, 'YYYY-MM') AS order_month,
    currency_code,
    COUNT(*) AS orders_count,
    ROUND(SUM(total)::numeric, 2) AS total_turnover
FROM afisha.purchases
GROUP BY order_month, currency_code
ORDER BY order_month, currency_code;
