CREATE EXTERNAL TABLE ext_tpcds.customer_demographics (like :DB_SCHEMA_NAME.customer_demographics)  
LOCATION (:LOCATION)
FORMAT 'CSV' (DELIMITER '|' NULL AS '' ESCAPE AS E'\\') ENCODING 'LATIN1';
