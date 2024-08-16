package Cpanel::Exim::Config::NAT;

# cpanel - Cpanel/Exim/Config/NAT.pm                Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exim::Config::NAT - NAT configuration for Exim

=head1 SYNOPSIS

=cut

our $_INCLUDE_FILE = '/var/cpanel/cpnat.exim.conf';

#----------------------------------------------------------------------

use constant KILLCF => (
    'extra_local_interfaces',
    'hide extra_local_interfaces',
);

=head2 config_file_section()

Returns exim configuration file includes to support
NAT if cpnat is enabled.

=cut

sub config_file_section {
    require Cpanel::Autodie::More::Lite;
    if ( Cpanel::Autodie::More::Lite::exists($_INCLUDE_FILE) ) {
        return "\n# --- NAT configuration\n.include_if_exists $_INCLUDE_FILE\n\n";
    }

    return q<>;
}

=head2 sync($public_ips_ar)

Takes an arrayref of public ips and updates
the exim config include file's extra_local_interfaces
directive.  This is currently called when we rebuild
the NAT configuration in Cpanel::NAT::Build

=cut

sub sync {
    my ($public_ips_ar) = @_;

    my @ips = grep { length } @$public_ips_ar;

    if ( @ips < @$public_ips_ar ) {
        warn "Empty-string given as public NAT IP!";
    }

    if (@ips) {
        require Cpanel::FileUtils::Write;
        Cpanel::FileUtils::Write::overwrite( $_INCLUDE_FILE, "extra_local_interfaces = <; " . join( ';', @ips ) . "\n", 0644 );
    }
    else {
        require Cpanel::Autowarn;
        Cpanel::Autowarn::unlink($_INCLUDE_FILE);
    }

    return;
}

1;
