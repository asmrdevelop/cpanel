<?php

// backend type (database, kolab, caldav, ical)
// Also, don't laugh, see /usr/local/cpanel/Cpanel/Services/Enabled.pm
// Apparently we disable "evil" services too...
if(file_exists("/etc/cpdavddisable") || file_exists("/etc/cpdavdisevil") ) {
    $config['calendar_driver'] = "database";
    $config['calendar_driver_default'] = "database";
} else {
    // cPanel patches kolab in order to allow multi-driver.
    $config['calendar_driver'] = ["database","caldav"];
    $config['calendar_driver_default'] = "caldav";
}

// default calendar view (agendaDay, agendaWeek, month)
$config['calendar_default_view'] = "agendaWeek";

// show a birthdays calendar from the user's address book(s)
$config['calendar_contact_birthdays'] = false;

// mapping of Roundcube date formats to calendar formats (long/short/agenda)
// should be in sync with 'date_formats' in main config
$config['calendar_date_format_sets'] = array(
  'yyyy-MM-dd' => array('MMM d yyyy',   'M-d',  'ddd MM-dd'),
  'dd-MM-yyyy' => array('d MMM yyyy',   'd-M',  'ddd dd-MM'),
  'yyyy/MM/dd' => array('MMM d yyyy',   'M/d',  'ddd MM/dd'),
  'MM/dd/yyyy' => array('MMM d yyyy',   'M/d',  'ddd MM/dd'),
  'dd/MM/yyyy' => array('d MMM yyyy',   'd/M',  'ddd dd/MM'),
  'dd.MM.yyyy' => array('dd. MMM yyyy', 'd.M',  'ddd dd.MM.'),
  'd.M.yyyy'   => array('d. MMM yyyy',  'd.M',  'ddd d.MM.'),
);

// timeslots per hour (1, 2, 3, 4, 6)
$config['calendar_timeslots'] = 2;

// show this number of days in agenda view
$config['calendar_agenda_range'] = 60;

// first day of the week (0-6)
$config['calendar_first_day'] = 1;

// first hour of the calendar (0-23)
$config['calendar_first_hour'] = 6;

// working hours begin
$config['calendar_work_start'] = 6;

// working hours end
$config['calendar_work_end'] = 18;

// show line at current time of the day
$config['calendar_time_indicator'] = true;

// default alarm settings for new events.
// this is only a preset when a new event dialog opens
// possible values are <empty>, DISPLAY, EMAIL
$config['calendar_default_alarm_type'] = '';

// default alarm offset for new events.
// use ical-style offset values like "-1H" (one hour before) or "+30M" (30 minutes after)
$config['calendar_default_alarm_offset'] = '-15M';

// how to colorize events:
// 0: according to calendar color
// 1: according to category color
// 2: calendar for outer, category for inner color
// 3: category for outer, calendar for inner color
$config['calendar_event_coloring'] = 0;

// event categories
$config['calendar_categories'] = array(
  'Personal' => 'c0c0c0',
      'Work' => 'ff0000',
    'Family' => '00ff00',
   'Holiday' => 'ff6600',
);

// enable users to invite/edit attendees for shared events organized by others
$config['calendar_allow_invite_shared'] = true;

// allow users to accecpt iTip invitations who are no explicitly listed as attendee.
// this can be the case if invitations are sent to mailing lists or alias email addresses.
$config['calendar_allow_itip_uninvited'] = true;

// controls the visibility/default of the checkbox controlling the sending of iTip invitations
// 0 = hidden  + disabled
// 1 = hidden  + active
// 2 = visible + unchecked
// 3 = visible + active
$config['calendar_itip_send_option'] = 3;

// Action taken after iTip request is handled. Possible values:
// 0 - no action
// 1 - move to Trash
// 2 - delete the message
// 3 - flag as deleted
// folder_name - move the message to the specified folder
$config['calendar_itip_after_action'] = 0;

// enable asynchronous free-busy triggering after data changed
$config['calendar_freebusy_trigger'] = false;

// free-busy information will be displayed for user calendars if available
// 0 - no free-busy information
// 1 - enabled in all views
// 2 - only in quickview
$config['calendar_include_freebusy_data'] = 1;

$domain = getenv('HTTP_HOST');
if(empty($domain)) $domain = 'mail.' . getenv('DOMAIN');

// Set to '' in order to use PHP's mail() function for email delivery.
// To override the SMTP port or connection method, provide a full URL like 'tls://somehost:587'
$config['calendar_itip_smtp_server'] = $domain;

// SMTP username used to send (anonymous) itip messages
$config['calendar_itip_smtp_user'] = getenv('REMOTE_USER');

// SMTP password used to send (anonymous) itip messages
$config['calendar_itip_smtp_pass'] = getenv('REMOTE_PASSWORD');

// show virtual invitation calendars (Kolab driver only)
$config['kolab_invitation_calendars'] = false;

// Base URL to build fully qualified URIs to access calendars via CALDAV
// The following replacement variables are supported:
// %h - Current HTTP host
// %u - Current webmail user name
// %n - Calendar name
// %i - Calendar UUID
// $config['calendar_caldav_url'] = 'http://%h/iRony/calendars/%u/%i';

// This is the default caldav server (ideally for cPDAVd)
$config['calendar_show_weekno'] = 0;
$config['calendar_caldav_server'] = 'https://127.0.0.1:2080/';
?>
