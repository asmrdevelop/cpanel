package Cpanel::DAV::Server;

# cpanel - Cpanel/DAV/Server.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DAV::Server

=head1 DESCRIPTION

This is a base class for C<cpdavd> and C<cpdavd-dormant>.

=cut

#----------------------------------------------------------------------

use Cpanel::ServiceConfig::cpdavd ();

use Cpanel::DAV::Ports ();

#----------------------------------------------------------------------

=head1 SUBCLASS INTERFACE

Define the following to have a working subclass of this class:

=head2 I<CLASS>->_run( $PORTS_AR )

This receives the output from C<Cpanel::DAV::Ports::get_ports()>.

=cut

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 I<CLASS>->run()

This verifies that the system role configuration requires cpdavd to run.
If so, it executes the C<_run()> method; otherwise, it prints a message
and returns.

Passes whether we're cpdavd_dormant in the case that it is so.

=cut

sub run {
    my ( $class, $is_cpdavd_dormant ) = @_;

    if ( Cpanel::ServiceConfig::cpdavd::is_needed() ) {
        $class->_run( Cpanel::DAV::Ports::get_ports($is_cpdavd_dormant) );
    }
    else {
        print Cpanel::ServiceConfig::cpdavd::unneeded_phrase() . "\n";
    }

    return;
}

1;
