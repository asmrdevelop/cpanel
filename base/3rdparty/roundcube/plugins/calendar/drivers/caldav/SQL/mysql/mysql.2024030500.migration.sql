START TRANSACTION;

DELETE FROM `calendars` WHERE `driver` <> 'database';
REPLACE INTO `system` (`name`, `value`) VALUES ('calendar-database-version', '2024030500');
REPLACE INTO `system` (`name`, `value`) VALUES ('calendar-caldav-version',   '2024030500');

COMMIT;
