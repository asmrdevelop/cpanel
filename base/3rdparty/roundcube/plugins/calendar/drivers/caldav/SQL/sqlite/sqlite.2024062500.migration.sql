BEGIN TRANSACTION;


DROP TABLE IF EXISTS caldav_events;
DROP TABLE IF EXISTS caldav_attachments;
DROP TABLE IF EXISTS caldav_calendars;

DELETE FROM calendars WHERE name = 'cPanel CALDAV';

INSERT OR REPLACE INTO system (name, value) VALUES ('calendar-database-version', '2024062500');
INSERT OR REPLACE INTO system (name, value) VALUES ('calendar-caldav-version', '2024062500');

END TRANSACTION;
