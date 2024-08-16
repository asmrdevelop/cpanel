BEGIN TRANSACTION;

DELETE FROM calendars WHERE driver <> 'database';
INSERT OR REPLACE INTO system (name, value) VALUES ('calendar-database-version', '2024030500');
INSERT OR REPLACE INTO system (name, value) VALUES ('calendar-caldav-version', '2024030500');

END TRANSACTION;
