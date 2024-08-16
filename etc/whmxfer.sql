DROP TABLE IF EXISTS `sessions`;
CREATE TABLE `sessions` (
  `sessionid` char(255) NOT NULL,
  `initiator` char(255) DEFAULT 'unknown',
  `creator` char(255) DEFAULT 'root',
  `pid` bigint(20) DEFAULT '0',
  `version` double DEFAULT '0',
  `target_host` char(255) DEFAULT NULL,
  `source_host` char(255) DEFAULT NULL,
  `state` bigint(20) DEFAULT '0',
  `starttime` datetime DEFAULT NULL,
  `endtime` datetime DEFAULT NULL,
  PRIMARY KEY (`sessionid`)
);
