/*
Script Purpose:
    This script creates a new databases for each layer of the Medallion architecture if they do not already exist. 
    If the databases exist, it is dropped and recreated.
	
WARNING:
    Running this script will drop the databases if they exist. 
    All data in the databases will be permanently deleted. Ensure you have proper backups before running this script.
*/

CREATE DATABASE IF NOT EXISTS bronze_layer;

CREATE DATABASE IF NOT EXISTS silver_layer;

CREATE DATABASE IF NOT EXISTS gold_layer;