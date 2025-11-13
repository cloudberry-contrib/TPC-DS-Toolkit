WITH x AS (SELECT duration FROM :report_schema.gen_data)
SELECT 'Seconds' as time, round(extract('epoch' from duration)) AS value
FROM x
UNION ALL
SELECT 'Minutes', round(extract('epoch' from duration)/60) AS minutes
FROM x
UNION ALL
SELECT 'Hours', round(extract('epoch' from duration)/(60*60)) AS hours 
FROM x;
