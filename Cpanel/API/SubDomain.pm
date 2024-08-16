package Cpanel::API::SubDomain;

# cpanel - Cpanel/API/SubDomain.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SubDomain ();

our %API = (
    addsubdomain => {
        needs_role => 'WebServer',
        allow_demo => 1,
    },
);

=head1 FUNCTIONS

=head2 addsubdomain($args, $results)

Takes the standard UAPI arguments and creates a subdomain by joining the
I<domain> and I<rootdomain> arguments with a single dot.

The I<canoff> parameter defaults to 1, but otherwise this call is identical to
the API 2 call of the same name.

=cut

sub addsubdomain {
    my ( $args,   $result ) = @_;
    my ( $status, $reason ) = Cpanel::SubDomain::_addsubdomain( $args->get('domain'), $args->get('rootdomain'), $args->get('canoff') // 1, $args->get('disallowdot'), $args->get('dir') );
    $result->raw_error($reason) unless $status;
    return $status;
}

1;
