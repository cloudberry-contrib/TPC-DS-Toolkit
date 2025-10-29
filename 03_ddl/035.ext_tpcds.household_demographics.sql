CREATE EXTERNAL TABLE ext_tpcds.household_demographics (like :DB_SCHEMA_NAME.household_demographics)
LOCATION (:LOCATION)
FORMAT 'CSV' (DELIMITER '|' NULL AS '' ESCAPE AS E'\\') ENCODING 'LATIN1';
