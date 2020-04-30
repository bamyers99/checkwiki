-- This file is prepared for use on Tools with:

-- $ mysql -htools-db < install.sql

-- Check if utf8 with 'SHOW SESSION VARIABLES LIKE 'character_set%'';

-- To use it in other environments, s51080__checkwiki_p needs to
-- be replaced with the name of the user database.

-- Create Checkwiki database --
CREATE DATABASE IF NOT EXISTS s51080__checkwiki_p;

-- Connect to database --
USE s51080__checkwiki_p;


-- Table cw_dumpscan --
CREATE TABLE `cw_dumpscan` (
  `Project` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Title` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Error` smallint(6) NOT NULL,
  `Notice` varchar(400) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `Ok` int(11) DEFAULT NULL,
  `Found` datetime DEFAULT NULL,
  PRIMARY KEY (`Project`,`Title`,`Error`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;


-- Table cw_error --
CREATE TABLE `cw_error` (
  `Project` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Title` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Error` smallint(6) NOT NULL,
  `Notice` varchar(400) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `Ok` int(11) DEFAULT NULL,
  `Found` datetime DEFAULT NULL,
  PRIMARY KEY (`Project`,`Title`,`Error`),
  KEY `Error_index` (`Error`,`Project`,`Ok`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;


-- Table cw_new --
CREATE TABLE `cw_new` (
  `Project` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Title` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  PRIMARY KEY (`Project`,`Title`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;


-- Table cw_overview --
CREATE TABLE `cw_overview` (
  `ID` int(11) DEFAULT NULL,
  `Project` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `LANG` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `Errors` bigint(20) DEFAULT NULL,
  `Done` bigint(20) DEFAULT NULL,
  `LAST_DUMP` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `LAST_UPDATE` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `Project_Page` varchar(400) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `Translation_Page` varchar(400) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`Project`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;


-- Table cw_overview_errors --
CREATE TABLE `cw_overview_errors` (
  `project` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `ID` smallint(6) NOT NULL DEFAULT '0',
  `Errors` mediumint(9) DEFAULT NULL,
  `Done` mediumint(9) DEFAULT NULL,
  `Name` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `Name_Trans` varchar(400) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `Prio` smallint(6) DEFAULT NULL,
  `Text` varchar(4000) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `Text_Trans` varchar(4000) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`project`,`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;


-- Table cw_meta --
CREATE TABLE `cw_meta` (
  `Project` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `templates` varchar(250) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `Metaparam` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;

-- Table cw_template --
CREATE TABLE `cw_template` (
  `Project` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Templates` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Error` smallint(6) NOT NULL
-- PRIMARY KEY (Project, Templates, Error) )  Thinks References and Références are the same.  Thus when both are added, one won't be because Primary Key would be identical.
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;


-- Table cw_whitelist --
CREATE TABLE `cw_whitelist` (
  `Project` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Title` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `Error` smallint(6) NOT NULL,
  `OK` tinyint(4) NOT NULL,
  PRIMARY KEY (`Project`,`Title`,`Error`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
