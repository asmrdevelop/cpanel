package Cpanel::DnsUtils::Config;

# cpanel - Cpanel/DnsUtils/Config.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig ();
use Cpanel::OS                 ();

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Config - Determine how bind is configured

=head1 SYNOPSIS

    use Cpanel::DnsUtils::Config;

    my $zone_dir = Cpanel::DnsUtils::Config::find_zonedir();

    my $using_jail = Cpanel::DnsUtils::Config::usenamedjail();

=cut

=head2 find_zonedir

Returns the path that dns zones are stored in on this system

=cut

sub find_zonedir {
    if ( -e '/etc/namedb' ) {
        return '/etc/namedb';
    }
    if ( -e '/var/lib/named/chroot/var/named/master' && usenamedjail() ) {
        return '/var/lib/named/chroot/var/named/master';
    }
    return '/var/named';
}

=head2 usenamedjail

Returns 1 if bind is jailed, Returns 0 if bind is not jailed.

=cut

sub usenamedjail {
    Cpanel::OS::assert_unreachable_on_ubuntu();
    if ( -s '/etc/sysconfig/named' ) {
        my $named_sysconfig = Cpanel::Config::LoadConfig::loadConfig('/etc/sysconfig/named');
        return (

            ( length $named_sysconfig->{'USE_JAIL'} && $named_sysconfig->{'USE_JAIL'} =~ m/^[\"\'\s]*yes[\"\'\s]*$/i ) ||

              ( length $named_sysconfig->{'NAMED_RUN_CHROOTED'} && $named_sysconfig->{'NAMED_RUN_CHROOTED'} =~ m/^[\"\'\s]*yes[\"\'\s]*$/i )
        ) ? 1 : 0;
    }
    return 0;
}

1;
