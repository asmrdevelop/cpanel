CREATE TABLE IF NOT EXISTS kolab_alarms (
  alarm_id VARCHAR(255) NOT NULL,
  user_id INTEGER NOT NULL,
  notifyat DATETIME DEFAULT NULL,
  dismissed TINYINT(3) NOT NULL DEFAULT '0',
  PRIMARY KEY(alarm_id,user_id)
);

CREATE INDEX IF NOT EXISTS ix_kolab_alarms_user_id ON kolab_alarms(user_id);

CREATE TABLE IF NOT EXISTS itipinvitations (
  token VARCHAR(64) NOT NULL PRIMARY KEY,
  event_uid VARCHAR(255) NOT NULL,
  user_id INTEGER NOT NULL DEFAULT '0',
  event TEXT NOT NULL,
  expires DATETIME DEFAULT NULL,
  cancelled TINYINT(3) NOT NULL DEFAULT '0'
);

CREATE INDEX IF NOT EXISTS ix_itipinvitations_uid ON itipinvitations(event_uid,user_id);

INSERT INTO system (name, value) VALUES ('calendar-caldav-version', '2014041700');
