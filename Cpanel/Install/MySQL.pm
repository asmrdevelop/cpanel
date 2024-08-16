package Cpanel::Install::MySQL;

# cpanel - Cpanel/Install/MySQL.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::OS      ();
use Cpanel::SysPkgs ();

=head1 NAME

Cpanel::Install::MySQL

=head1 SYNOPSIS

    use Cpanel::Install::MySQL ();
    Cpanel::Install::MySQL::install_mysql_keys();

=head1 DESCRIPTION

This is a breakout/refactor of code for installing
things related to MySQL previously within scripts/cpanel_initial_install.
This was done to simplify testing.

=head1 FUNCTIONS

=head2 install_mysql_keys

Installs MySQL repository keys to the RPM or APT subsystem, depending on the OS.
Currently only the MySQL key is imported on APT, but this will need to be updated
later in order for MariaDB keys to additionally be preinstalled.

returns whether or not all keys successfully installed.

=cut

sub install_mysql_keys {
    my $syspkgs_obj = Cpanel::SysPkgs->new();
    my $keys_hr     = Cpanel::OS::db_package_manager_key_params();
    my $num_failed  = scalar( @{ $keys_hr->{'keys'} } ) - scalar( grep { $syspkgs_obj->can( $keys_hr->{'method'} )->( $syspkgs_obj, $_ ) } @{ $keys_hr->{'keys'} } );
    return !$num_failed;
}

1;
