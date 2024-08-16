package Whostmgr::Transfers::Session::Config;

# cpanel - Whostmgr/Transfers/Session/Config.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles ();

our $VERSION                 = '2.3';
our $SESSION_DIR             = '/var/cpanel/transfer_sessions';
our $MAX_SESSION_AGE         = ( 86400 * 30 );                                  # 30 days in seconds
our $MAX_IDLE_TIME           = ( 3600 * 4 );                                    # 4 hours in seconds
our $DBNAME                  = 'whmxfer';
our $NUMPHASES               = 2;
our $UNRESTRICTED            = 1;
our $RESTRICTED              = 0;
our $MODULES_DIR             = '/Whostmgr/Transfers/Systems';
our $CUSTOM_PERL_MODULES_DIR = $Cpanel::ConfigFiles::CUSTOM_PERL_MODULES_DIR;
our $CPANEL_PERL_MODULES_DIR = $Cpanel::ConfigFiles::CPANEL_ROOT;

# Order matters here. We won't start restoring the next queue until
# all of the items in the queue are transferred
our %ITEMTYPE_NAMES = (
    1000 => 'FeatureListRemoteRoot',
    1045 => 'BackupsRemoteRoot',
    1050 => 'EximRemoteRoot',
    1052 => 'ThemesRemoteRoot',
    1054 => 'ApacheRemoteRoot',
    1060 => 'GreyListRemoteRoot',
    1062 => 'AutoSSLOptionsRemoteRoot',
    1070 => 'ModSecurityRemoteRoot',
    1056 => 'MySQLRemoteRoot',
    1058 => 'WHMConfRemoteRoot',
    1061 => 'HulkRemoteRoot',
    2000 => 'PackageRemoteRoot',
    3000 => 'AccountRemoteRoot',
    4000 => 'AccountRemoteUser',
    5000 => 'AccountLocal',
    6000 => 'LegacyAccountBackup',
    7000 => 'AccountUpload',
    8000 => 'RearrangeAccount',
    9000 => 'MailboxConversion',
);

1;
