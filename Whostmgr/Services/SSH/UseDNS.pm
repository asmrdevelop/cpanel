package Whostmgr::Services::SSH::UseDNS;

# cpanel - Whostmgr/Services/SSH/UseDNS.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Services::SSH::UseDNS

=head1 DESCRIPTION

This module houses logic to disable SSHD’s C<UseDNS> setting, which
interacts poorly with cPHulk.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::ServerTasks             ();
use Whostmgr::Services::SSH::Config ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $did_disable_yn = disable_if_needed()

Returns a boolean that indicates whether C<UseDNS> was disabled.

This throws a generic exception on failure.

=cut

sub disable_if_needed {
    my $sshd_config_obj = Whostmgr::Services::SSH::Config->new();
    my $usedns_setting  = $sshd_config_obj->get_config('UseDNS');

    my $usedns_is_on = !defined $usedns_setting || $usedns_setting !~ /no/i;

    if ($usedns_is_on) {
        eval { $sshd_config_obj->set_config( { 'UseDNS' => 'no' } ); 1 } or do {
            my $err = $@;
            die locale()->maketext( 'The system failed to disable [asis,SSHD]’s “[_1]” setting due to an error: [_2]', 'UseDNS', "$err" );
        };

        Cpanel::ServerTasks::queue_task( ['CpServicesTasks'], 'restartsrv sshd' );

        return 1;
    }

    return 0;
}

1;
