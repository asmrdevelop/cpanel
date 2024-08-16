package Cpanel::RemoteAPI;

# cpanel - Cpanel/RemoteAPI.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::RemoteAPI - Base class for API calls to remote cPanel & WHM

=head1 SYNOPSIS

See subclasses for examples.

=head1 DESCRIPTION

This base class exists to abstract away logic that runs an API call on
a remote cPanel & WHM machine.

Please do not extend this base class or subclasses with methods that
directly make assumptions about the implementation.

=head1 EXTRA CONSTRUCTOR PARAMETERS

The following are recognized and passed to L<cPanel::PublicAPI>’s
constructor internally:

=over

=item * C<timeout>

=item * C<connect_timeout>

=item * C<error_log>

=back

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::RemoteAPI::Base';

# This is what we want to abstract over.
use cPanel::PublicAPI ();

use Cpanel::HTTP::Tiny::FastSSLVerify ();

# overridden in tests
our $_PUBLICAPI_CLASS = 'cPanel::PublicAPI';

#----------------------------------------------------------------------

sub _already_connected ($self) {
    return $self->{'_publicapi'};
}

# Called from subclasses.
sub _publicapi_obj {
    my ($self) = @_;

    return $self->{'_publicapi'} //= do {
        my %api_args = %{ $self->{'_api_args'} };

        # “timeout” and “connect_timeout” are funny: if our caller
        # gives them we want to honor them, but if our caller *doesn’t*
        # give them then we want to supply this module’s defaults.
        # In no circumstance do we want cPanel::PublicAPI’s defaults.
        # (FYI: As of this writing, that’s timeout=300.)

        my %xtra_http_tiny_args = %api_args{ 'timeout', 'connect_timeout' };

        $xtra_http_tiny_args{'connect_timeout'} //= 10;
        $xtra_http_tiny_args{'timeout'}         //= 120;

        $_PUBLICAPI_CLASS->new(
            %api_args,

            http_tiny_creator => sub (@http_tiny_create_args) {
                return Cpanel::HTTP::Tiny::FastSSLVerify->new(
                    @http_tiny_create_args,
                    %xtra_http_tiny_args,
                );
            },
        );
    };
}

sub _NEW_OPTS ($) {
    return ( 'timeout', 'connect_timeout', 'error_log' );
}

1;
