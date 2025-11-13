SELECT split_part(description, '.', 2) AS id,  case max(tuples) when -1 then 'ERROR' else max(tuples)::text end as tuples, round(min(extract('epoch' from duration))) AS duration
FROM :report_schema.sql
where id > 1
GROUP BY split_part(description, '.', 2)
ORDER BY id;