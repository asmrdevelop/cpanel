#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/backend/puttykey.cgi   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Form   ();
use Cpanel::SSH    ();
use Whostmgr::ACLS ();

sub hasfeature { 1 }

Whostmgr::ACLS::init_acls();

#WHM's SSH key management is solely for managing the root account's SSH keys
if ( Whostmgr::ACLS::hasroot() ) {
    my %FORM = Cpanel::Form::parseform();

    my $file = $FORM{'file'};
    my $putty_text;

    if ($file) {
        $putty_text = Cpanel::SSH::_converttoppk(
            'file'       => $file,
            'passphrase' => $FORM{'passphrase'} || undef,
        );

        if ($putty_text) {
            print "Content-Type: application/octet-stream\r\n";
            print "Content-Disposition: attachment;filename=$file.ppk\r\n\r\n";
            print $putty_text;
        }
    }

    if ( !$putty_text ) {
        $ENV{'HTTP_STATUS'} = 404;
        print "HTTP/1.1 404 Not Found\r\n";
        print "Connection: close\r\n";
        print "Content-Type: text/plain\r\n\r\n";
        print $Cpanel::CPERROR{'ssh'} . "\n";
    }
}
