package Whostmgr::CgiApp::Base;

# cpanel - Whostmgr/CgiApp/Base.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Whostmgr::ACLS ();
use Cpanel::Carp   ();

sub new {
    my ( $class, %OPTS ) = @_;

    Cpanel::Carp::enable();

    # suppress logs the errors to the error_log
    # but does not spew to stdout
    $Cpanel::Carp::OUTPUT_FORMAT = 'suppress';

    Whostmgr::ACLS::init_acls();

    $Cpanel::appname           ||= 'whostmgr';
    $Whostmgr::Session::app    ||= 'whostmgr';
    $Whostmgr::Session::binary ||= 0;

    my $allowed_to_run = 0;

    my $self = { 'acls' => $OPTS{'acls'} };

    bless $self, $class;

    if ( $OPTS{'acls'} ) {
        foreach my $acl ( @{ $OPTS{'acls'} } ) {
            if ( Whostmgr::ACLS::checkacl($acl) ) {
                $allowed_to_run = 1;
                last;
            }
        }
    }
    else {
        $allowed_to_run = Whostmgr::ACLS::hasroot();
    }

    if ( !$allowed_to_run ) {
        $self->_permission_denied();
    }

    return $self;
}

sub run {
    my ( $self, $coderef ) = @_;

    return $coderef->();
}

sub _permission_denied {
    print "Status: 403\r\nContent-type: text/plain\r\n\r\nForbidden";
    exit();
}

1;
