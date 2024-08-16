<?php

/**
 +-----------------------------------------------------------------------+
 |                                                                       |
 | cpanelicsimport                         Copyright 2022 cPanel, L.L.C. |
 |                                                  All rights reserved. |
 | copyright@cpanel.net                               https://cpanel.net |
 | This code is subject to the cPanel license.                           |
 | Unauthorized copying is prohibited.                                   |
 |                                                                       |
 +-----------------------------------------------------------------------+
*/

class cpanelicsimport extends rcube_plugin
{
    private const PLUGIN_VERSION = 'v11.108';

    /**
     * Information about this plugin that is queried by roundcube.
     */
    private const PLUGIN_INFO = [
        'name' => 'cpanelicsimport',
        'vendor' => 'cPanel, LLC',
        'version' => self::PLUGIN_VERSION,
        'license' => 'cPanel License',
        'uri' => 'https://cpanel.net'
    ];

    const LOG_DISABLED = 0;
    const LOG_FAILURE = 1;
    const LOG_VERBOSE = 2;
    const TOUCH_FILE = '.cpanel_ics_import';

    public $task = 'login';
    public $rc;
    public $home;
    private $_drivers = null;
    private $_cals = null;
    private $_cal_driver_map = null;
    private $log_level;

    function init()
    {
        $this->add_hook('login_after', array($this, 'attemptImport'));
    }

    /**
     * Initialize an rcmail instance for our user
     * and load our configuration
     */
    private function initialize()
    {
        $this->rc = rcmail::get_instance();
        // Load plugin's config file
        $this->load_config();
        $this->log_level = $this->rc->config->get('cpanel_log_level');
        $this->require_plugin('libcalendaring');
    }

    function attemptImport($params)
    {
        $this->initialize();
        $this->rc = rcube::get_instance();
        $user = str_replace('..', '', $this->rc->user->get_username());
        $srcdir = $this->rc->config->get('cpanel_data_dir');
        if( posix_getpwuid(posix_geteuid())['name'] === 'cpanelroundcube' ) {
            # XXX There's no way to *really* be sure what the cpusername is!
            # This is due to $_ENV['HOME'] being all we really get here to
            # indicate "who does this webmail user belong to".
            # "Let's just hope real hard they never change their username but
            # not their homedir name!"
            # Anyways, $user here is the webmail user, not the cpuser, so we
            # cannot use that.
            $cpuser = substr( $_ENV['HOME'], strrpos( $_ENV['HOME'], "/" ) + 1 );
            $srcdir = "/var/cpanel/userhomes/cpanelroundcube/${cpuser}/icals/";
        }
        $run_once = $this->rc->config->get('cpanel_run_once');
        $charset = $this->rc->config->get('cpanel_file_charset');
        if(!is_dir($srcdir)){ mkdir(slashify($srcdir), 0711, true); }
        $touch_file = slashify($srcdir) . cpanelicsimport::TOUCH_FILE . "_${user}";
        if (file_exists($touch_file)) {
            if (!$run_once) { //cleanup old touch file
                if (!unlink($touch_file)) {
                    $this->log("Unable to remove touch file for ${user}", cpanelicsimport::LOG_FAILURE);
                }
            } else { // dont run again
                $this->log("Touch file ${touch_file} exists for ${user} and cpanel_run_once is true, exiting");
                return;
            }
        }
        //create touch file so we only run once, whether success or failure
        if ($run_once) {
            if (touch($touch_file)) {
                $this->log("Touch file created for ${user}");
            } else {
                $this->log("Error creating touch file ${touch_file} for ${user}",
                    cpanelicsimport::LOG_FAILURE);
            }
        }
        $ical_backup = slashify($srcdir) . $user . '.ics';
        if ( file_exists($ical_backup) && filesize($ical_backup) ) {
            $this->require_plugin('calendar');

            // Init calendar plugin partially -- just enough to do what
            // we need
            $cal_obj = new calendar(rcube_plugin_api::get_instance());
            $cal_obj->rc = rcube::get_instance();
            $cal_obj->load_config();
            $cal_obj->lib             = libcalendaring::get_instance();
            $cal_obj->timezone        = $cal_obj->lib->timezone;
            $cal_obj->gmt_offset      = $cal_obj->lib->gmt_offset;
            $cal_obj->dst_active      = $cal_obj->lib->dst_active;
            $cal_obj->timezone_offset = $cal_obj->gmt_offset / 3600 - $cal_obj->dst_active;

            // Get the default calendar and import to it.
            $cal_id = $cal_obj->get_default_calendar()['id'];

            try {
                // we will import past events too, except anything more than a century ago
                $count = $cal_obj->import_from_file($ical_backup, $cal_id, date_create("now -100 years"), $errors);
            } catch (exception $e) {
                $errors = "Caught exception when running import_from_file: " . $e->getTraceAsString();
            }
            $this->log("IMPORTED " . $count);
            if(!empty($errors)) {
                $this->log("ERRORS " . $errors);
            }
        }
        return $params;
    }

    private function log($message, $level = cpanelicsimport::LOG_VERBOSE)
    {
        if ($this->log_level && $level <= $this->log_level) {
            error_log("[CPANELICSIMPORT: ${message}]");
        }
    }
}
