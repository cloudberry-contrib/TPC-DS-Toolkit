SELECT split_part(description, '.', 1) as schema_name, round(extract('epoch' from duration)) AS seconds 
FROM tpcds_reports.analyze
WHERE tuples = -1
ORDER BY 1;
