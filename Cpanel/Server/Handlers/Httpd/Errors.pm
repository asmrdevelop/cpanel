package Cpanel::Server::Handlers::Httpd::Errors;

# cpanel - Cpanel/Server/Handlers/Httpd/Errors.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::Httpd::Errors

=head1 SYNOPSIS

    die Cpanel::Server::Handlers::Httpd::Errors::unknown_domain($http_host);

=head1 DESCRIPTION

This module contains exception-producing logic for different cases where the
explanation for the failure isn’t already implicit from the HTTP status code.
For example, an HTTP 404 probably shouldn’t go here, but HTTP 400 can (with
various different reasons).

The idea is partly to prevent duplication of the localized error strings
and partly also to ensure that we use the same status codes for the same
conditions.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 unknown_domain()

Returns (does B<NOT> throw) the appropriate exception for when the given
HTTP_HOST isn’t a recognized domain.

=cut

sub unknown_domain {

    # This is what Apache httpd does. So, we imitate.
    return Cpanel::Exception::create('cpsrvd::NotFound');
}

1;
