SELECT split_part(description, '.', 2) as table_name, to_char(sum(tuples), '999,999,999,999,999') as tuples, round(sum(extract('epoch' from duration))) AS seconds 
FROM :report_schema.load 
WHERE tuples > 0 
GROUP BY split_part(description, '.', 2)
ORDER BY 1;
