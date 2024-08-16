package Whostmgr::Resellers::Rename;

# cpanel - Whostmgr/Resellers/Rename.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Resellers::Rename - Tools to rename a reseller

=head1 SYNOPSIS

    use Whostmgr::Resellers::Rename;

    Whostmgr::Resellers::Rename::rename_reseller($old_reseller_name, $new_reseller_name)

=cut

use Whostmgr::Resellers::Change     ();
use Whostmgr::Resellers             ();
use Cpanel::Domains                 ();
use Whostmgr::Packages              ();
use Whostmgr::Limits::PackageLimits ();
use Whostmgr::Limits                ();
use Cpanel::Debug                   ();

=head2 rename_reseller( $old_reseller_name, $new_reseller_name )

Changes the username of a reseller in cPanel's internal datbases.

=cut

sub rename_reseller {
    my ( $old_reseller_name, $new_reseller_name ) = @_;

    my ( $status, $msg ) = Whostmgr::Resellers::Change::change_users_owners( $old_reseller_name, $new_reseller_name );

    if ( !$status ) {
        Cpanel::Debug::log_warn("Unable to change ownership of users for $old_reseller_name to $new_reseller_name");
    }

    Whostmgr::Packages::change_reseller( $old_reseller_name, $new_reseller_name );

    my $all_reseller_limits_opts = Whostmgr::Limits::load_all_reseller_limits(1);
    $all_reseller_limits_opts->{'data'}->{$new_reseller_name} = $all_reseller_limits_opts->{'data'}->{$old_reseller_name};
    delete $all_reseller_limits_opts->{'data'}->{$old_reseller_name};
    Whostmgr::Limits::saveresellerlimits($all_reseller_limits_opts);

    Whostmgr::Limits::PackageLimits::change_reseller( $old_reseller_name, $new_reseller_name );

    Whostmgr::Resellers::change_user_name( $old_reseller_name, $new_reseller_name );

    Cpanel::Domains::change_deleteddomains_reseller( $old_reseller_name, $new_reseller_name );

    rename '/var/cpanel/' . $old_reseller_name . '.acct', '/var/cpanel/' . $new_reseller_name . '.acct';

    foreach my $subdir (qw(cluster news webtemplates)) {
        rename '/var/cpanel/' . $subdir . '/' . $old_reseller_name, '/var/cpanel/' . $subdir . '/' . $new_reseller_name;
    }

    return ( 1, "Reseller data updated" );
}

1;
