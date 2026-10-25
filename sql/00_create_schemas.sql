-- SBA 7(a) loan-risk project: create schemas before raw table and views.
-- Run in the intended PostgreSQL database.

SELECT current_database() AS database_name,
	   current_user AS connected_user,
	   version() AS postgresql_version;



-- Create a schema for original SBA records
CREATE SCHEMA IF NOT EXISTS raw;

-- Create a schema for analytical views
CREATE SCHEMA IF NOT EXISTS analytics;
