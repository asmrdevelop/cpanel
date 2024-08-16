package Cpanel::Dovecot::Compat;

# cpanel - Cpanel/Dovecot/Compat.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AdvConfig::dovecot::utils ();
use Cpanel::Version::Compare          ();

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::Compat

=head1 SYNOPSIS

use Cpanel::Dovecot::Compat ();
if( Cpanel::Dovecot::Compat::has_ssl_min_protocol() ) {
	...
}

=head1 DESCRIPTION

This module is used to determine what version dependent configuration settings to used based upon
the installed Dovecot version.

=head1 FUNCTIONS


=cut

=head2 has_ssl_min_protocol()

This function determines if the currently installed version of Dovecot should use the
ssl_min_protocol config setting over the ssl_protocols. This function returns 1 if
the currently installed dovecot version supports the ssl_min_protocol and 0 if it does not.

=head3 Returns

This function returns 1 if the currently installed dovecot version supports the
ssl_min_protocol and 0 if it does not.

=head3 Exceptions

None.

=cut

sub has_ssl_min_protocol {
    return Cpanel::Version::Compare::compare( _get_dovecot_version(), '>=', '2.3.0' ) ? 1 : 0;
}

sub _get_dovecot_version {
    my $full_version = Cpanel::AdvConfig::dovecot::utils::get_dovecot_version();
    return ( split( / /, $full_version ) )[0];
}

1;
