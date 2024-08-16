package Whostmgr::Templates::Command::Resellers;

# cpanel - Whostmgr/Templates/Command/Resellers.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig ();
use Cpanel::ConfigFiles        ();

use Whostmgr::ACLS               ();
use Whostmgr::Templates::Command ();

my $list_of_resellers;

=head1 DESCRIPTION

Utility functions to process cached command.tmpl files for resellers

=head1 SUBROUTINES

=head2 _get_resellers_list

=head3 Purpose

Get a list of all resellers on the system

=cut

sub _get_resellers_list {
    return $list_of_resellers if $list_of_resellers;

    my $resellers_file = Cpanel::Config::LoadConfig::loadConfig( $Cpanel::ConfigFiles::RESELLERS_FILE, undef, ':' );
    $list_of_resellers = [ 'root', keys %{$resellers_file} ];

    return $list_of_resellers;
}

=head2 _process_reseller

=head3 Purpose

Process command.tmpl and cache result for one reseller

=cut

sub _process_reseller {
    my ($reseller) = @_;

    %Whostmgr::ACLS::ACL = ();
    local $ENV{'REMOTE_USER'} = $reseller;
    Whostmgr::ACLS::init_acls();

    Whostmgr::Templates::Command::clear_cache();
    Whostmgr::Templates::Command::clear_cache_key();
    Whostmgr::Templates::Command::cached_load();

    return;
}

=head2 process_all_resellers

=head3 Purpose

Process cached command.tmpl files for all resellers

=cut

sub process_all_resellers {
    $list_of_resellers ||= _get_resellers_list();

    local $ENV{'BATCH_RESELLERS_PROCESSING'} = 1;

    foreach my $reseller ( @{$list_of_resellers} ) {
        _process_reseller($reseller);
    }

    return;
}

1;
