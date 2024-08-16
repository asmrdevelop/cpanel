package Cpanel::Mysql::Hosts;

# cpanel - Cpanel/Mysql/Hosts.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Mysql::Hosts

=head1 SYNOPSIS

    my $hosts_hr = get_hosts_lookup();

    my @access_hosts = get_system_access_hosts();

=head1 DESCRIPTION

This module contains logic to return various hosts used in MySQL grants.

=cut

use Cpanel::Context                  ();
use Cpanel::DIp::MainIP              ();
use Cpanel::Hostname                 ();
use Cpanel::LoadFile                 ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::NAT                      ();

our $_SYSTEM_ACCESS_HOSTS_FILE = '/var/cpanel/mysqlaccesshosts';

=head1 FUNCTIONS

=head2 $hosts_hr = get_hosts_lookup()

This returns all of the hosts that should be added to a local MySQL
C<USAGE> grant.

Note that this is for C<local> grants. If the MySQL server is remote,
you’ll need an additional grant for the server that the remote
server “sees” when the cP server attempts to log in. See
L<Cpanel::Mysql::Passwd> for an implementation of this.

=cut

sub get_hosts_lookup {
    my @hosts_list = (
        'localhost',

        Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root') || (),

        Cpanel::Hostname::gethostname(),

        Cpanel::DIp::MainIP::getmainserverip(),

        get_system_access_hosts(),
    );

    # Always include the 'hostname' and 'mainip'
    # as that is what the Transfers system (restores) does.
    #
    # If we do not add them here, then there will be a
    # disconnect, wherein these entries will be left in place
    # even after a DB user has been removed from a DB, etc.
    my %HOSTLIST;
    @HOSTLIST{@hosts_list} = ();

    if ( Cpanel::NAT::is_nat() ) {
        for my $name ( keys %HOSTLIST ) {
            my $public_ip = Cpanel::NAT::get_public_ip($name) or next;
            $HOSTLIST{$public_ip} = undef;
        }
    }

    return \%HOSTLIST;
}

sub get_system_access_hosts {
    Cpanel::Context::must_be_list();

    return grep { length } map { tr<A-Z><a-z>r } split m<\s+>, Cpanel::LoadFile::load_if_exists($_SYSTEM_ACCESS_HOSTS_FILE) // q<>;
}

1;
