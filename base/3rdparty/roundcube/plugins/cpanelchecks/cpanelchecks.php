<?php

/**
 +-----------------------------------------------------------------------+
 |                                                                       |
 | cpanelchecks                            Copyright 2022 cPanel, L.L.C. |
 |                                                  All rights reserved. |
 | copyright@cpanel.net                               https://cpanel.net |
 | This code is subject to the cPanel license.                           |
 | Unauthorized copying is prohibited.                                   |
 |                                                                       |
 +-----------------------------------------------------------------------+
*/

class cpanelchecks extends rcube_plugin
{
    private const PLUGIN_VERSION = 'v11.120';

    /**
     * Information about this plugin that is queried by roundcube.
     */
    private const PLUGIN_INFO = [
        'name' => 'cpanelchecks',
        'vendor' => 'cPanel, LLC',
        'version' => self::PLUGIN_VERSION,
        'license' => 'cPanel License',
        'uri' => 'https://cpanel.net'
    ];

    const LOG_DISABLED = 0;
    const LOG_FAILURE = 1;
    const LOG_VERBOSE = 2;
    const TOUCH_FILE = '.skip_cpanel_checks';

    public $task = 'login';
    private $rc;
    private $rcmail;
    private $log_level;

    private $db_schema_updates = [ '2022120700', '2023030100' ];

    function init()
    {
        $this->add_hook('login_after', array($this, 'performChecks'));
    }

    function performChecks($params)
    {
        $this->initialize();
        // read database config
        $db = $this->rc->get_dbh();
        $dbtype = $db->db_provider;
        // Install/upgrade schema if needed
        $this->_check_schema($dbtype);
        return $params;
    }

    /**
     * Initialize an rcmail instance for our user
     * and load our configuration
     */
    private function initialize()
    {
        $this->rc = rcube::get_instance();
        $this->rcmail = rcmail::get_instance();
        // Load plugin's config file
        $this->load_config();
        $this->log_level = $this->rcmail->config->get('cpanel_log_level');
    }

    private function _check_schema($dbtype) {
        $this->_schema_check($dbtype, 'libkolab-version');
        $this->_schema_check($dbtype, 'calendar-database-version');
        $this->_schema_check($dbtype, 'calendar-caldav-version');
        return;
    }

    private function _schema_check($dbtype, $pluginkey) {
        $query = $this->rc->db->query(
            "SELECT `value` FROM `system` WHERE name=?",
            $pluginkey,
        );

        // RCube db accessor has no simple "fetch", so SELECT count(*) actually
        // is counterproductive. Just do an empty check on no hits
        $record = $this->rc->db->fetch_assoc();

        // If you don't do this, you'll die later due to db locked.
        // Tolerate it being a bool, as that's another fail state of query :(
        if( !is_bool($query) ) {
            $query->closeCursor();
        }

        if(empty($record)) {
            $this->_schema_install($dbtype,$pluginkey);
        } else {
            foreach( $this->db_schema_updates as $db_schema_version ) {
                if( intval($record['value']) >= intval($db_schema_version) ) continue;
                $this->_schema_update($dbtype, $db_schema_version, $pluginkey);
            }
        }
        return;
    }

    private function _schema_install($dbtype, $pluginkey) {
        $specifics = explode('-', preg_replace('/-version$/', '', $pluginkey));
        if(!empty($specifics[1])) {
            $file = realpath( "/usr/local/cpanel/base/3rdparty/roundcube/plugins/" . $specifics[0] . "/drivers/" . $specifics[1] . "/SQL/" . $dbtype . ".initial.sql" );
        } else {
            $file = realpath( "/usr/local/cpanel/base/3rdparty/roundcube/plugins/" . $specifics[0] . "/SQL/" . $dbtype . ".initial.sql" );
        }
        return $this->_do_schema_sql($file, $dbtype);
    }

    private function _schema_update($dbtype, $db_schema_version, $pluginkey) {
        $specifics = explode('-', preg_replace('/-version$/', '', $pluginkey));
        if(!empty($specifics[1])) {
            $file = realpath( "/usr/local/cpanel/base/3rdparty/roundcube/plugins/" . $specifics[0] . "/drivers/" . $specifics[1] . "/SQL/" . $dbtype . '.' . $db_schema_version . '.migration.sql' );
        } else {
            $file = realpath( "/usr/local/cpanel/base/3rdparty/roundcube/plugins/" . $specifics[0] . "/SQL/" . $dbtype . '.' . $db_schema_version . '.migration.sql' );
        }
        if(empty($file)) return;
        return $this->_do_schema_sql($file, $dbtype);
    }

    private function _do_schema_sql($file, $dbtype, $retry_on_lock=true) {
        if(file_exists($file)) {
            error_log("Schema updates detected in $file, applying now...");
            $query_raw = file_get_contents($file);
            $this->rc->db->dbh->exec($query_raw);
            $error = $this->rc->db->dbh->errorInfo();
            if ($error[0] != '00000') {
                if( $dbtype == 'sqlite' && $error[1] == 6 && $retry_on_lock ) {
                    # retry once on DB locked
                    //return $this->_do_schema_sql($file, $dbtype, false);
                }
                error_log("Schema update query from $file failed with code " . $error[1] . ": " . $error[2]);
                return false;
            }
        } else {
            error_log("Couldn't find schema update file: $file");
        }
        return true;
    }

    private function log($message, $level = cpanelchecks::LOG_VERBOSE)
    {
        if ($this->log_level && $level <= $this->log_level) {
            error_log("[CPANELSQLCHECK: ${message}]");
        }
    }
}
