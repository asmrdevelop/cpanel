package Cpanel::Server::Handlers::Httpd::SetUid;

# cpanel - Cpanel/Server/Handlers/Httpd/SetUid.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#----------------------------------------------------------------------

use Cpanel::Domain::Owner                   ();
use Cpanel::Server::Handlers::Httpd::Errors ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $username = determine_setuid_user_by_host( $HTTP_HOST )

Returns the name of the user as whom cpsrvd should answer the HTTP request,
based on the HTTP C<Host> header.

If no such username can be determined, the return of
C<Cpanel::Server::Handlers::Httpd::Errors::unknown_domain()> is thrown.

=cut

sub determine_setuid_user_by_host {
    my ($http_host) = @_;

    my $domain_owner = Cpanel::Domain::Owner::get_owner_or_undef($http_host);

    if ( !$domain_owner ) {
        die Cpanel::Server::Handlers::Httpd::Errors::unknown_domain();
    }

    return $domain_owner;
}

1;
