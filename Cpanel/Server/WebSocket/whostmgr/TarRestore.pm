package Cpanel::Server::WebSocket::whostmgr::TarRestore;

# cpanel - Cpanel/Server/WebSocket/whostmgr/TarRestore.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::whostmgr::TarRestore

=head1 DESCRIPTION

This class allows a WHM user to upload files via tar over WebSocket.

This class extends L<Cpanel::Server::WebSocket::AppBase::TarRestore>
and L<Cpanel::Server::WebSocket::whostmgr>.

=head1 INTERFACE

The following parameters (sent via URL query string) are recognized:

=over

=item * C<directory> - The parent directory into which to unpack the
archive contents.

=item * C<setuid_username> - The user as whom to extract the archive
contents.

=back

See L<Cpanel::Server::WebSocket::AppBase::TarRestore> for interface
details that don’t pertain specifically to the WHM environment.

=head2 Access Control

This module is available only to root and root-enabled resellers.

It may be useful to allow use by non-root resellers as long as the
C<FileStorage> role is enabled on the system.

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::Server::WebSocket::AppBase::TarRestore
  Cpanel::Server::WebSocket::whostmgr
);

use Cpanel::Form ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<OBJ>->new( $SERVER_OBJ )

See L<Cpanel::Server::Handlers::WebSocket>.

=cut

sub new ( $class, $server_obj ) {

    my $self = $class->SUPER::new($server_obj);

    my $form_hr = Cpanel::Form::parseform();

    my @req = qw( directory setuid_username );

    my @missing = grep { !$form_hr->{$_} } @req;
    die "Need: @missing" if @missing;

    $self->{'_streamer_args'} = [ %{$form_hr}{@req} ];

    return $self;
}

1;
