/*M!999999\- enable the sandbox mode */ 
-- MariaDB dump 10.19-11.8.3-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: tools.db.svc.wikimedia.cloud    Database: s51080__checkwiki_p
-- ------------------------------------------------------
-- Server version	10.6.22-MariaDB-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*M!100616 SET @OLD_NOTE_VERBOSITY=@@NOTE_VERBOSITY, NOTE_VERBOSITY=0 */;

--
-- Table structure for table `cw_dumpscan`
--

DROP TABLE IF EXISTS `cw_dumpscan`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `cw_dumpscan` (
  `Title` varchar(255) NOT NULL DEFAULT '',
  `Error` smallint(6) NOT NULL,
  `Notice` varchar(400) DEFAULT NULL,
  `Ok` int(11) DEFAULT NULL,
  `Found` datetime DEFAULT NULL,
  `ProjectNo` smallint(6) NOT NULL DEFAULT 0,
  PRIMARY KEY (`ProjectNo`,`Title`,`Error`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `cw_error`
--

DROP TABLE IF EXISTS `cw_error`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `cw_error` (
  `Title` varchar(255) NOT NULL DEFAULT '',
  `Error` smallint(6) NOT NULL,
  `Notice` varchar(400) DEFAULT NULL,
  `Ok` int(11) DEFAULT NULL,
  `Found` datetime DEFAULT NULL,
  `ProjectNo` smallint(6) NOT NULL DEFAULT 0,
  PRIMARY KEY (`ProjectNo`,`Title`,`Error`),
  UNIQUE KEY `proj_err_found_title` (`ProjectNo`,`Error`,`Found`,`Title`),
  KEY `Error_index` (`Error`,`ProjectNo`,`Ok`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `cw_meta`
--

DROP TABLE IF EXISTS `cw_meta`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `cw_meta` (
  `Project` varchar(20) NOT NULL,
  `templates` varchar(250) DEFAULT NULL,
  `Metaparam` varchar(100) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `cw_new`
--

DROP TABLE IF EXISTS `cw_new`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `cw_new` (
  `Title` varchar(255) NOT NULL DEFAULT '',
  `ProjectNo` smallint(6) NOT NULL DEFAULT 0,
  PRIMARY KEY (`ProjectNo`,`Title`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `cw_overview`
--

DROP TABLE IF EXISTS `cw_overview`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `cw_overview` (
  `ID` int(11) DEFAULT NULL,
  `Project` varchar(20) NOT NULL DEFAULT '',
  `LANG` varchar(100) DEFAULT NULL,
  `Errors` bigint(20) DEFAULT NULL,
  `Done` bigint(20) DEFAULT NULL,
  `LAST_DUMP` varchar(100) DEFAULT NULL,
  `LAST_UPDATE` varchar(100) DEFAULT NULL,
  `Project_Page` varchar(400) DEFAULT NULL,
  `Translation_Page` varchar(400) DEFAULT NULL,
  PRIMARY KEY (`Project`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `cw_overview_errors`
--

DROP TABLE IF EXISTS `cw_overview_errors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `cw_overview_errors` (
  `Project` varchar(20) NOT NULL DEFAULT '',
  `ID` smallint(6) NOT NULL DEFAULT 0,
  `Errors` mediumint(9) DEFAULT NULL,
  `Done` mediumint(9) DEFAULT NULL,
  `Name` varchar(255) DEFAULT NULL,
  `Name_Trans` varchar(400) DEFAULT NULL,
  `Prio` smallint(6) DEFAULT NULL,
  `Text` varchar(4000) DEFAULT NULL,
  `Text_Trans` varchar(4000) DEFAULT NULL,
  `ProjectNo` smallint(6) NOT NULL DEFAULT 0,
  PRIMARY KEY (`ID`,`ProjectNo`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `cw_template`
--

DROP TABLE IF EXISTS `cw_template`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `cw_template` (
  `Project` varchar(20) NOT NULL,
  `Templates` varchar(100) NOT NULL,
  `Error` smallint(6) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `cw_whitelist`
--

DROP TABLE IF EXISTS `cw_whitelist`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `cw_whitelist` (
  `Project` varchar(20) NOT NULL,
  `Title` varchar(255) NOT NULL DEFAULT '',
  `Error` smallint(6) NOT NULL,
  `OK` tinyint(4) NOT NULL,
  PRIMARY KEY (`Project`,`Title`,`Error`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*M!100616 SET NOTE_VERBOSITY=@OLD_NOTE_VERBOSITY */;

-- Dump completed on 2025-12-17 20:52:26
