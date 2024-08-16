#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/build_locale_databases.pl
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::SafeRun::Dynamic ();
use Whostmgr::ACLS           ();

_check_acls();

print "Content-type: text/plain\r\n\r\n";

$|++;
Cpanel::SafeRun::Dynamic::livesaferun(
    'prog'      => [ '/usr/local/cpanel/bin/servers_queue', 'queue', 'build_locale_databases' ],
    'formatter' => sub {
        my $output = shift;
        if ( $output =~ /^Id: TQ:TaskQueue/ ) {
            return 'Locale database scheduled for rebuild';
        }
        else {
            return $output;
        }
    },
);

sub _check_acls {
    Whostmgr::ACLS::init_acls();

    if ( !Whostmgr::ACLS::checkacl('locale-edit') ) {
        print "Status: 401\r\nContent-type: text/plain\r\n\r\n";
        print "Permission denied.\n";
        exit();
    }
}
