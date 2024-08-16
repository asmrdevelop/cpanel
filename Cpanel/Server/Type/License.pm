package Cpanel::Server::Type::License;

# cpanel - Cpanel/Server/Type/License.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Server::Type                     ();
use Cpanel::Server::Type::Profile::Constants ();

BEGIN { *is_ea4_allowed = *is_cpanel }

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::License - Helper module check license state

=head1 SYNOPSIS

    use Cpanel::Server::Type::License ();

    Cpanel::Server::Type::License::is_cpanel();

=head1 DESCRIPTION

This module provides additional utility functions to check the state of a role or profile that
are note needed in the base Cpanel::Server::Type.  In order to keep Cpanel::Server::Type
as small as possible they exist in this namespace

=head1 FUNCTIONS

=head2 is_full_license

Determines if the server has a full cPanel license

At the current time, this means that a valid license was found and lists cpanel as a
product. The only current known cases where this is not true are if an invalid license
is encountered or a DNS-only license is used.

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

Returns true if the server has a full license, false if not

=back

=back

=cut

sub is_full_license {

    return !$Cpanel::Server::Type::DNSONLY_MODE if defined $Cpanel::Server::Type::DNSONLY_MODE;

    if ( Cpanel::Server::Type::_read_license() ) {
        return $Cpanel::Server::Type::PRODUCTS{'cpanel'} ? 1 : 0;
    }

    return -e Cpanel::Server::Type::_get_dnsonly_file_path() ? 0 : 1;
}

=head2 is_cpanel

Determines if the server is a full cPanel installation with all features enabled.

Note that this method returns false if the server profile is set to anything besides
STANDARD. To perform a check to see if the server is using a full license instead of
a DNS-only license, use is_full_license().

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<SCALAR>

Returns 1 if the server is a full cPanel installation, 0 if not

=back

=back

=cut

sub is_cpanel {
    return 0 if !is_full_license() || _is_license_restricted_node();
    return 1;
}

sub _is_license_restricted_node {
    return Cpanel::Server::Type::is_dnsonly() || Cpanel::Server::Type::get_producttype() ne Cpanel::Server::Type::Profile::Constants::STANDARD();
}

#----------------------------------------------------------------------

1;
