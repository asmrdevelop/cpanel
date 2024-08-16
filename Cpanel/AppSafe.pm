package Cpanel::AppSafe;

# cpanel - Cpanel/AppSafe.pm                       Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel ();

## webmail functionality data structures
my ( $loaded_webmail_appsafe, %APPSAFE );

# Used by thirdparty developers to mark their API calls as safe for use in webmail
sub makewebmailsafe {
    my ( $module, $api, $function ) = @_;
    if ( !$loaded_webmail_appsafe ) {
        load_webmail_appsafe();
    }
    $APPSAFE{'webmail'}{$module}{$api}{$function} = 1
      if defined $module && defined $api && defined $function;

    return 1;
}

sub checksafefunc {
    my ( $module, $func, $api ) = @_;
    if ( !$loaded_webmail_appsafe ) {
        load_webmail_appsafe();
    }

    #Walk this way to prevent auto-vivification.
    my $ok = $APPSAFE{$Cpanel::appname};
    $ok &&= $ok->{$module};
    $ok &&= $ok->{$api};
    $ok &&= $ok->{$func};

    return defined($ok) ? int($ok) : 0;
}

sub load_webmail_appsafe {
    $loaded_webmail_appsafe = 1;
    ## note: int( $APPSAFE{$appname}{$module}{$apiver}{$func} )
    $APPSAFE{'webmail'} = {
        'dprint'                 => { '1' => { 'dprint'                 => 1 } },
        'formprint'              => { '1' => { 'formprint'              => 1 } },
        'get_cjt_lex_script_tag' => { '1' => { 'get_cjt_lex_script_tag' => 1 } },
        'get_cjt_url'            => { '1' => { 'get_cjt_url'            => 1 } },
        'get_js_lex_script_tag'  => { '1' => { 'get_js_lex_script_tag'  => 1 } },
        'getcharset'             => { '1' => { 'getcharset'             => 1 } },
        'include'                => { '1' => { 'include'                => 1 } },
        'jsprint'                => { '1' => { 'jsprint'                => 1 } },
        'langprint'              => { '1' => { 'langprint'              => 1 } },
        'print'                  => { '1' => { 'print'                  => 1 } },
        'printhelp'              => { '1' => { 'printhelp'              => 1 } },
        'printvar'               => { '1' => { 'printvar'               => 1 } },
        'rawinclude'             => { '1' => { 'rawinclude'             => 1 } },
        'relinclude'             => { '1' => { 'relinclude'             => 1 } },
        'relrawinclude'          => { '1' => { 'relrawinclude'          => 1 } },
        'relrawincludelex'       => { '1' => { 'relrawincludelex'       => 1 } },
        'setvar'                 => { '1' => { 'setvar'                 => 1 } },
        'sprint'                 => { '1' => { 'sprint'                 => 1 } },
        'unsafeprint'            => { '1' => { 'unsafeprint'            => 1 } },
        'uriprint'               => { '1' => { 'uriprint'               => 1 } },
        'version'                => { '1' => { 'version'                => 1 } },

        #----------------------------------------------------------------------

        Batch        => { 3 => { strict => 1 } },
        'BoxTrapper' => {
            '1' => {
                'accountmanagelist'          => 1,
                'changestatus'               => 1,
                'cleancfgfilelist'           => 1,
                'downloadmessage'            => 1,
                'editmsg'                    => 1,
                'fetchcfgfile'               => 1,
                'getboxconfdir'              => 1,
                'getboxconfdiruri'           => 1,
                'listmsgs'                   => 1,
                'logcontrols'                => 1,
                'messageaction'              => 1,
                'multimessageaction'         => 1,
                'resetmsg'                   => 1,
                'savecfgfile'                => 1,
                'saveconf'                   => 1,
                'showautowhitelist'          => 1,
                'showemails'                 => 1,
                'showfromname'               => 1,
                'showlog'                    => 1,
                'showmessage'                => 1,
                'showmin_spam_score_deliver' => 1,
                'showqueue'                  => 1,
                'showqueuesearch'            => 1,
                'showqueuetime'              => 1,
                'showwhitelist_by_assoc'     => 1,
                'status'                     => 1,
                'statusbutton'               => 1,
            },
            '3' => {
                'get_status'           => 1,
                'set_status'           => 1,
                'get_log'              => 1,
                'list_queued_messages' => 1,
                'get_configuration'    => 1,
                'save_configuration'   => 1,
                'get_message'          => 1,
                'deliver_messages'     => 1,
                'delete_messages'      => 1,
                'ignore_messages'      => 1,
                'whitelist_messages'   => 1,
                'blacklist_messages'   => 1,
                'process_messages'     => 1,
                'get_email_template'   => 1,
                'save_email_template'  => 1,
                'reset_email_template' => 1,
                'list_email_templates' => 1,
                'get_forwarders'       => 1,
                'set_forwarders'       => 1,
                'get_blocklist'        => 1,
                'set_blocklist'        => 1,
                'get_allowlist'        => 1,
                'set_allowlist'        => 1,
                'get_ignorelist'       => 1,
                'set_ignorelist'       => 1,
            },
        },
        'Branding' => {
            '1' => {
                'text'    => 1,
                'include' => 1,    ## uapi
            },
            '3' => {
                'include'                          => 1,
                'get_available_applications'       => 1,
                'get_application_information'      => 1,
                'get_applications'                 => 1,
                'get_information_for_applications' => 1
            }
        },
        'Chkservd' => {
            '1' => {
                'geteximport_ssl' => 1,
                'geteximport'     => 1
            },
            '3' => {
                'get_exim_ports'     => 1,
                'get_exim_ports_ssl' => 1,
            }
        },
        'Contactus' => {
            '2' => { 'isenabled'  => 1 },
            '3' => { 'is_enabled' => 1 },
        },
        ContactInformation => {
            3 => {
                set_email_addresses   => 1,
                unset_email_addresses => 1,
            },
        },
        'CustInfo' => {
            '2' => {
                'contactprefs'       => 1,
                'savecontactinfo'    => 1,
                'displaycontactinfo' => 1,
            },
        },
        'CPDAVD' => {
            '3' => {
                'add_delegate'      => 1,
                'update_delegate'   => 1,
                'remove_delegate'   => 1,
                'list_delegates'    => 1,
                'list_users'        => 1,
                'manage_collection' => 1,
            },
        },
        'DAV' => {
            '3' => {
                'get_calendar_contacts_config'  => 1,
                'is_dav_service_enabled'        => 1,
                'has_shared_global_addressbook' => 1,
            },
        },
        'Email' => {
            '1' => {
                'hasmaildir'             => 1,
                'listmaildomainsopt'     => 1,
                'listmaildomains'        => 1,
                'listmaildomainsoptndef' => 1,
                'has_spam_as_acl'        => 1,
                'getarsbody'             => 1,
                'getarsinterval'         => 1,
                'getarsstart'            => 1,
                'getarsstop'             => 1,
                'getarsfrom'             => 1,
                'listforwardstable'      => 1,
                'getmailserver'          => 1,
                'getpopquota'            => 1,
                'check_roundcube'        => 1,
                'getarssubject'          => 1,
                'printdomainoptions'     => 1,
                'listforwards'           => 1,
                'delforward'             => 1,
                'delautoresponder'       => 1,
                'getmailserveruser'      => 1,
                'passwdpop'              => 1,
                'getarshtml'             => 1,
                'listautoresponders'     => 1,
                'addautoresponder'       => 1,
                'addforward'             => 1,
                'getarscharset'          => 1,
                'getreg'                 => 1,
                'spamstatus'             => 1,
            },
            '2' => {
                'loadfilter'                  => 1,
                'listmaildomains'             => 1,
                'accountname'                 => 1,
                'filtername'                  => 1,
                'browseboxes'                 => 1,
                'storefilter'                 => 1,
                'filteractions'               => 1,
                'listforwards'                => 1,
                'listpops'                    => 1,
                'fetchautoresponder'          => 1,
                'deletefilter'                => 1,
                'getabsbrowsedir'             => 1,
                'filterrules'                 => 1,
                'getdiskusage'                => 1,
                'listautoresponders'          => 1,
                'filterlist'                  => 1,
                'listpopswithdisk'            => 1,
                'tracefilter'                 => 1,
                'addforward'                  => 1,
                'checkmaindiscard'            => 1,
                'reorderfilters'              => 1,
                'has_delegated_mailman_lists' => 1,
                'listlists'                   => 1,
            },
            '3' => {
                'listlists'                         => 1,
                'get_main_account_disk_usage_bytes' => 1,
                'has_plaintext_authentication'      => 1,
                'get_charsets'                      => 1,
                'list_mail_domains'                 => 1,
                'get_client_settings'               => 1,
                'dispatch_client_settings'          => 1,
                'list_pops'                         => 1,
                'list_pops_with_disk'               => 1,
                'get_disk_usage'                    => 1,
                'passwd_pop'                        => 1,
                'get_pop_quota'                     => 1,
                'stats_db_status'                   => 1,
                'get_webmail_settings'              => 1,
                'list_forwarders'                   => 1,
                'add_forwarder'                     => 1,
                'delete_forwarder'                  => 1,

                'list_auto_responders'  => 1,
                'get_auto_responder'    => 1,
                'add_auto_responder'    => 1,
                'delete_auto_responder' => 1,

                'list_filters'         => 1,
                'account_name'         => 1,
                'get_filter'           => 1,
                'reorder_filters'      => 1,
                'store_filter'         => 1,
                'delete_filter'        => 1,
                'trace_filter'         => 1,
                'browse_mailbox'       => 1,
                'generate_mailman_otp' => 1,
                'list_lists'           => 1,

                'has_delegated_mailman_lists' => 1,
                'fts_rescan_mailbox'          => 1,

                'add_spam_filter'            => 1,
                'get_spam_settings'          => 1,
                'disable_spam_autodelete'    => 1,
                'get_mailbox_autocreate'     => 1,
                'enable_mailbox_autocreate'  => 1,
                'disable_mailbox_autocreate' => 1,

                'trace_delivery' => 1,
            }
        },
        'EmailTrack' => {
            '2' => {
                'search' => 1,
                'stats'  => 1
            }
        },
        'ExternalAuthentication' => {
            '3' => {
                'configured_modules' => 1,
                'get_authn_links'    => 1,
                'remove_authn_link'  => 1,
            }
        },
        'Locale' => {
            '1' => { 'maketext' => 1 },    ## no extract maketext
            '2' => {
                'get_locale_name'   => 1,
                'get_encoding'      => 1,
                'get_html_dir_attr' => 1
            },
            '3' => {
                'get_attributes' => 1,
            },
        },
        'MagicRevision' => { '1' => { 'uri' => 1 } },
        'Mailboxes'     => {
            '3' => {
                'get_mailbox_status_list'           => 1,
                'expunge_mailbox_messages'          => 1,
                'expunge_messages_for_mailbox_guid' => 1,
            },
        },
        'Mysql'  => { '3' => { 'get_server_information' => 1 } },
        'NVData' => {
            '2' => {
                'get' => 1,    ## uapi
                'set' => 1
            },
            '3' => { 'get' => 1 },
        },
        'Parser' => {
            '1' => { 'firstfile_relative_uri' => 1 },
            '3' => { 'firstfile_relative_uri' => 1 }
        },
        'PasswdStrength' => {
            '2' => {
                'appstrengths'          => 1,
                'get_required_strength' => 1,
            },
        },
        'Personalization' => {
            '3' => {
                'get' => 1,
                'set' => 1,
            }
        },
        'SetLang'       => { '1' => { 'listlangsopt' => 1 } },
        'SourceIPCheck' => {
            '2' => {
                'savesecquestions'  => 1,
                'resetsecquestions' => 1,
                'listips'           => 1,
                'getaccount'        => 1,
                'loadsecquestions'  => 1,
                'delip'             => 1,
                'addip'             => 1
            }
        },
        'SSL' => {
            '1' => { 'getcnname'   => 1 },
            '3' => { 'get_cn_name' => 1 },
        },
        'StatsBar' => { '2' => { 'stat'           => 1 } },
        'Styles'   => { '3' => { 'current'        => 1 } },
        'Themes'   => { '3' => { 'get_theme_base' => 1 } },
        'UI'       => {
            '1' => { 'confirm'  => 1 },
            '2' => { 'paginate' => 1 }
        },
        'WebmailApps' => {
            '2' => { 'listwebmailapps'   => 1 },
            '3' => { 'list_webmail_apps' => 1 }
        },
        TwoFactorAuth => {
            3 => {
                set_user_configuration      => 1,
                get_user_configuration      => 1,
                generate_user_configuration => 1,
                remove_user_configuration   => 1,
                get_team_user_configuration => 1,
            },
        },

    };

    return;

}

1;
