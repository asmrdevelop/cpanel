set @exist := (SELECT count(*) FROM information_schema.statistics WHERE table_name = 'calendars' AND index_name = 'name' AND table_schema = database());
set @sqlstmt := if( @exist = 0, 'select ''Unique index for name does not exist, skipping.''', 'DROP INDEX name ON calendars');
PREPARE stmt FROM @sqlstmt;
EXECUTE stmt;
REPLACE INTO `system` (`name`, `value`) VALUES ('calendar-database-version', '2024030600');
REPLACE INTO `system` (`name`, `value`) VALUES ('calendar-caldav-version',   '2024030600');
