package Cpanel::Config::LoadCpConf;

# cpanel - Cpanel/Config/LoadCpConf.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::LoadCpConf - Load the cpanel.config file

=head1 SYNOPSIS

    use Cpanel::Config::LoadCpConf ();

    my $cpconf = Cpanel::Config::CpConfGuard::loadcpconf();

    my $cpconf = Cpanel::Config::CpConfGuard::loadcpconf_not_copy();


=head1 DESCRIPTION

# longer description...

=cut

# Code moved to Cpanel::Config::CpConfGuard to assure validation of config data happens if possible
use Cpanel::Config::CpConfGuard ();

=head2 loadcpconf()

Returns a hashref of key values from /var/cpanel/config.config

This is a copy that is safe to modify.

If you are sure that all code that the hashref will be passed to
will not modify it you should use loadcpconf_not_copy as it is
much faster.

=cut

sub loadcpconf {
    my $cpconf = Cpanel::Config::CpConfGuard->new( 'loadcpconf' => 1 )->config_copy;
    return wantarray ? %$cpconf : $cpconf;
}

=head2 loadcpconf_not_copy()

This function works exactly the same as loadcpconf() except it does not make
a copy of the hashref.

If you are not sure consumers of the hashref will not modify it you should
use loadcpconf()

=cut

sub loadcpconf_not_copy {

    # Attempt to short circut and use the cache without creating the
    # object which slows this down quite a bit
    if ( !defined $Cpanel::Config::CpConfGuard::memory_only && $Cpanel::Config::CpConfGuard::MEM_CACHE_CPANEL_CONFIG_MTIME ) {
        my ( $cache, $cache_is_valid ) = Cpanel::Config::CpConfGuard::get_cache();
        if ($cache_is_valid) {
            return wantarray ? %$cache : $cache;
        }
    }

    my $cpconf_obj = Cpanel::Config::CpConfGuard->new( 'loadcpconf' => 1 );
    my $cpconf     = $cpconf_obj->{'data'} || $cpconf_obj->{'cache'} || {};
    return wantarray ? %$cpconf : $cpconf;
}

# predeclaring the sub allows us to avoid "'no warnings 'once';" which requires compiler shenanigans so why not just avoid it here?
sub clearcache;
*clearcache = *Cpanel::Config::CpConfGuard::clearcache;

1;
