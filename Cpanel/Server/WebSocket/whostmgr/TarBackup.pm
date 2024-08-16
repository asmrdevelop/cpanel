package Cpanel::Server::WebSocket::whostmgr::TarBackup;

# cpanel - Cpanel/Server/WebSocket/whostmgr/TarBackup.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::whostmgr::TarBackup

=head1 DESCRIPTION

This class allows a WHM user to download files via tar over WebSocket.

This class extends L<Cpanel::Server::WebSocket::AppBase::TarBackup>
and L<Cpanel::Server::WebSocket::whostmgr>.

This module complements L<Cpanel::Server::WebSocket::AppBase::TarRestore>.
It accepts the same parameters. For now it always backs
up the entire contents of the C<directory> parameter. We can add flexibility
down the line if needs dictate.

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::Server::WebSocket::AppBase::TarBackup
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

    my @paths;

    if ( $form_hr->{paths} ) {
        require Whostmgr::API::1::Utils;
        @paths = Whostmgr::API::1::Utils::get_length_required_arguments( $form_hr, "paths" );
    }
    else {
        @paths = ("./");
    }

    $self->{'_streamer_args'} = [ %{$form_hr}{@req}, paths => \@paths ];

    return $self;
}

1;
