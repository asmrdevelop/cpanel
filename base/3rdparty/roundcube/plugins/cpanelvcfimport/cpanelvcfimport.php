<?php

/**
 +-----------------------------------------------------------------------+
 |                                                                       |
 | cpanelvcfimport                         Copyright 2022 cPanel, L.L.C. |
 |                                                  All rights reserved. |
 | copyright@cpanel.net                               https://cpanel.net |
 | This code is subject to the cPanel license.                           |
 | Unauthorized copying is prohibited.                                   |
 |                                                                       |
 +-----------------------------------------------------------------------+
*/

class cpanelvcfimport extends rcube_plugin
{
    private const PLUGIN_VERSION = 'v11.108';

    /**
     * Information about this plugin that is queried by roundcube.
     */
    private const PLUGIN_INFO = [
        'name' => 'cpanelvcfimport',
        'vendor' => 'cPanel, LLC',
        'version' => self::PLUGIN_VERSION,
        'license' => 'cPanel License',
        'uri' => 'https://cpanel.net'
    ];

    const LOG_DISABLED = 0;
    const LOG_FAILURE = 1;
    const LOG_VERBOSE = 2;
    const TOUCH_FILE = '.cpanel_vcf_import';

    public $task = 'login';
    private $rcmail;
    private $contacts;
    private $group;
    private $log_level;

    function init()
    {
        $this->add_hook('login_after', array($this, 'attemptImport'));
    }

    function attemptImport($params)
    {
        $this->initialize();
        $user = str_replace('..', '', $this->rcmail->user->get_username());
        $srcdir = $this->rcmail->config->get('cpanel_data_dir');
        if( posix_getpwuid(posix_geteuid())['name'] === 'cpanelroundcube' ) {
            $cpuser = substr( $_ENV['HOME'], strrpos( $_ENV['HOME'], "/" ) + 1 );
            $srcdir = "/var/cpanel/userhomes/cpanelroundcube/${cpuser}/vcards/";
        }
        $run_once = $this->rcmail->config->get('cpanel_run_once');
        $charset = $this->rcmail->config->get('cpanel_file_charset');
        $touch_file = slashify($srcdir) . cpanelvcfimport::TOUCH_FILE . "_${user}";
        if(!is_dir($srcdir)){ mkdir(slashify($srcdir), 0711, true); }
        if (file_exists($touch_file)) {
            if (!$run_once) { //cleanup old touch file
                if (!unlink($touch_file)) {
                    $this->log("Unable to remove touch file for ${user}",
                        cpanelvcfimport::LOG_FAILURE);
                }
            } else { // dont run again
                $this->log("Touch file ${touch_file} exists for ${user} and cpanel_run_once is true, exiting");
                return;
            }
        }
        $this->group = $this->get_contact_group($this->contacts);
        //create touch file so we only run once, whether success or failure
        if ($run_once) {
            if (touch($touch_file)) {
                $this->log("Touch file created for ${user}");
            } else {
                $this->log("Error creating touch file ${touch_file} for ${user}",
                    cpanelvcfimport::LOG_FAILURE);
            }
        }
        $vcard_backup = slashify($srcdir) . $user . '.vcf';
        if ( file_exists($vcard_backup) && filesize($vcard_backup) ) {
            $added_contacts = array();
            $vcards = array();
            $file_content = file_get_contents($vcard_backup);
            // let rcube_vcard do the hard work :-)
            $vcard_o = new rcube_vcard();
            $vcard_o->extend_fieldmap($this->contacts->vcard_map);
            $v_list = $vcard_o->import($file_content);
            if (!empty($v_list)) {
                $vcards = array_merge($vcards, $v_list);
            }
            $IMPORT_STATS = new stdClass;
            $IMPORT_STATS->names = array();
            $IMPORT_STATS->skipped_names = array();
            $IMPORT_STATS->countup = count($vcards);
            $IMPORT_STATS->inserted = $IMPORT_STATS->skipped = $IMPORT_STATS->invalid = $IMPORT_STATS->errors = 0;
            if ($replace) {
                $this->contacts->delete_all($this->contacts->groups && $with_groups < 2);
            }
            if ($with_groups) {
                $import_groups = $this->contacts->list_groups();
            }
            foreach ($vcards as $vcard) {
                $a_record = $vcard->get_assoc();
                // Generate contact's display name (must be before validation), the same we do in save.inc
                if (empty($a_record['name'])) {
                    $a_record['name'] = rcube_addressbook::compose_display_name($a_record, true);
                    // Reset it if equals to email address (from compose_display_name())
                    if ($a_record['name'] == $a_record['email'][0]) {
                        $a_record['name'] = '';
                    }
                }
                // skip invalid (incomplete) entries
                if (!$this->contacts->validate($a_record, true)) {
                    $IMPORT_STATS->invalid++;
                    continue;
                }
                // We're using UTF8 internally
                $email = $vcard->email[0];
                $email = rcube_utils::idn_to_utf8($email);
                $a_record['vcard'] = $vcard->export();
                $plugin = $this->rcmail->plugins->exec_hook('contact_create',
                    array('record' => $a_record, 'source' => null));
                $a_record = $plugin['record'];
                // insert record and send response
                if (!$plugin['abort'])
                    $success = $this->contacts->insert($a_record);
                else
                    $success = $plugin['result'];
                if ($success) {
                    // assign groups for this contact (if enabled)
                    if ($with_groups && !empty($a_record['groups'])) {
                        foreach (explode(',', $a_record['groups'][0]) as $group_name) {
                            if ($group_id = rcmail_import_group_id($group_name, $this->contacts, $with_groups == 1, $import_groups)) {
                                $this->contacts->add_to_group($group_id, $success);
                            }
                        }
                    }
                    // assign to 'Imported Contacts' group
                    if ($this->group) {
                        $this->contacts->add_to_group($this->group['id'], $success);
                    }
                    $IMPORT_STATS->inserted++;
                    $IMPORT_STATS->names[] = $a_record['name'] ?: $email;
                }
                else {
                    $IMPORT_STATS->errors++;
                }
            }
            $this->log("IMPORTED " . $IMPORT_STATS->inserted);
            $this->log("ERRORS " . $IMPORT_STATS->errors);
        }
        return $params;
    }

    /**
     * If the configuration requests it, create a new group
     * to add contacts to. If the group exists, create a new one with
     * a number such as Imported Contacts 2
     *
     * @param $rc_contacts rcube_contacts
     * @return mixed False on error, array with record props in success
     */
    private function get_contact_group($rc_contacts)
    {
        $group_name = $this->rcmail->config->get('cpanel_group_name');
        if ($group_name) {
            return $rc_contacts->create_group($group_name);
        }
        return false;
    }

    /**
     * Initialize an rcmail instance for our user
     * and load our configuration
     */
    private function initialize()
    {
        $this->rcmail = rcmail::get_instance();
        // Load plugin's config file
        $this->load_config();
        $this->log_level = $this->rcmail->config->get('cpanel_log_level');
        $this->contacts = $this->rcmail->get_address_book(null, true);
    }

    /**
     * Converts $str to $charset
     * if not charset is specified it will attempt to
     * determine the charset.
     * @param $str
     * @param null $charset
     * @return string
     */
    private function convert_charset($str, $charset = null)
    {
        if (!$charset) {
            $charset = rcube_charset::detect($str);
        }
        return rcube_charset::convert($str, $charset, RCUBE_CHARSET);
    }

    private function log($message, $level = cpanelvcfimport::LOG_VERBOSE)
    {
        if ($this->log_level && $level <= $this->log_level) {
            error_log("[CPANELVCFIMPORT: ${message}]");
        }
    }
}
