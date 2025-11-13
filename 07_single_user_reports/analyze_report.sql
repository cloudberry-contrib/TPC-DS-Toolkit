SELECT split_part(description, '.', 1) as schema_name, round(extract('epoch' from duration)) AS seconds 
FROM :report_schema.analyze
WHERE tuples = -1
ORDER BY 1;
