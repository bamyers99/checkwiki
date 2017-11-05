-- This file is prepared for use on Tools with:

-- $ mysql -htools-db < install.sql

-- Check if utf8 with 'SHOW SESSION VARIABLES LIKE 'character_set%'';

-- To use it in other environments, p50380g50450__checkwiki_p needs to
-- be replaced with the name of the user database.

-- Create Checkwiki database --
CREATE DATABASE IF NOT EXISTS p50380g50450__checkwiki_p;

-- Connect to database --
USE p50380g50450__checkwiki_p;


-- Table cw_dumpscan --
CREATE TABLE IF NOT EXISTS cw_dumpscan
(Project VARCHAR(20) NOT NULL,
 Title VARCHAR(250) NOT NULL,
 Error SMALLINT NOT NULL,
 Notice VARCHAR(400),
 Ok INT,
 Found DATETIME,
 PRIMARY KEY (Project, Title, Error) )
 CHARACTER SET utf8 COLLATE utf8_bin;


-- Table cw_error --
CREATE TABLE IF NOT EXISTS cw_error
(Project VARCHAR(20) NOT NULL,
 Title VARCHAR(250) NOT NULL,
 Error SMALLINT NOT NULL,
 Notice VARCHAR(400),
 Ok INT,
 Found DATETIME,
 PRIMARY KEY (Project, Title, Error) )
 CHARACTER SET utf8 COLLATE utf8_bin;
 CREATE INDEX Error_index ON cw_error (Error, Project, Ok);


-- Table cw_new --
CREATE TABLE IF NOT EXISTS cw_new
(Project VARCHAR(20) NOT Null,
 Title VARCHAR(250) NOT Null,
 PRIMARY KEY (Project, Title) )
 CHARACTER SET utf8 COLLATE utf8_bin;


-- Table cw_overview --
CREATE TABLE IF NOT EXISTS cw_overview
(ID SMALLINT,
 Project VARCHAR(20) NOT NULL,
 Lang VARCHAR(100),
 Errors MEDIUMINT,
 Done MEDIUMINT,
 Last_Dump VARCHAR(100),
 Last_Update VARCHAR(100),
 Project_Page VARCHAR(400),
 Translation_Page VARCHAR(400)
 PRIMARY KEY (Project) )
 CHARACTER SET utf8 COLLATE utf8_unicode_ci;


-- Table cw_overview_errors --
CREATE TABLE IF NOT EXISTS cw_overview_errors
(Project VARCHAR(20) NOT NULL,
 ID SMALLINT NOT NULL,
 Errors MEDIUMINT,
 Done MEDIUMINT,
 Name VARCHAR(255),
 Name_Trans VARCHAR(400),
 Prio SMALLINT,
 Text VARCHAR(4000),
 Text_Trans VARCHAR(4000)
 PRIMARY KEY (Project, ID) )
 CHARACTER SET utf8 COLLATE utf8_unicode_ci;


-- Table cw_meta --
CREATE TABLE IF NOT EXISTS cw_meta
(Project VARCHAR(20) NOT NULL,
 Templates VARCHAR(250) NOT NULL,
 Metaparam VARCHAR(100) NOT NULL )
 CHARACTER SET utf8 COLLATE utf8_unicode_ci;

-- Table cw_template --
CREATE TABLE IF NOT EXISTS cw_template
(Project VARCHAR(20) NOT NULL,
 Templates VARCHAR(100) NOT NULL,
 Error SMALLINT NOT NULL )
-- PRIMARY KEY (Project, Templates, Error) )  Thinks References and Références are the same.  Thus when both are added, one won't be because Primary Keey would be identical.
 CHARACTER SET utf8 COLLATE utf8_unicode_ci;


-- Table cw_whitelist --
CREATE TABLE IF NOT EXISTS cw_whitelist
(Project VARCHAR(20) NOT NULL, 
 Title VARCHAR(250) NOT NULL,
 Error SMALLINT NOT NULL,
 OK TINYINT NOT NULL,
 PRIMARY KEY (Project, Title, Error) )
 CHARACTER SET utf8 COLLATE utf8_bin;
