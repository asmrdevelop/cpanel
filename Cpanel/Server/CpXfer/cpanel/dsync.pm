package Cpanel::Server::CpXfer::cpanel::dsync;

# cpanel - Cpanel/Server/CpXfer/cpanel/dsync.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::CpXfer::cpanel::dsync

=head1 SYNOPSIS

n/a

=head1 DESCRIPTION

This implements cpsrvd’s C<cpxfer/dsync> endpoint. It’s meant to be
accessed via a high-level client module like L<Cpanel::Async::MailSync>.

=cut

#----------------------------------------------------------------------

use Cpanel::Dsync::Stream         ();
use Cpanel::Exception             ();
use Cpanel::Validate::EmailCpanel ();

use parent qw(
  Cpanel::Server::CpXfer
  Cpanel::Server::ModularApp::cpanel::ForbidDemo
);

#----------------------------------------------------------------------

sub _400_err ($msg) {
    return Cpanel::Exception::create_raw( 'cpsrvd::BadRequest', $msg );
}

sub _BEFORE_HEADERS ( $self, $form_ref ) {

    my $account = $form_ref->{'account'};

    die _400_err('Need “account”!') if !length $account;

    my $acct_exists;

    if ( !Cpanel::Validate::EmailCpanel::is_valid($account) ) {
        die _400_err("Malformed account name: $account");
    }

    if ( 0 == index( $account, '_mainaccount@' ) ) {
        my $domain = $self->get_server_obj()->auth()->get_main_domain();
        $acct_exists = $account eq "_mainaccount\@$domain";
    }
    else {
        require Cpanel::Email::Exists;

        my ( $user, $domain ) = Cpanel::Validate::EmailCpanel::get_name_and_domain($account);

        $acct_exists = Cpanel::Email::Exists::pop_exists( $user, $domain );
    }

    if ( !$acct_exists ) {
        die _400_err("Nonexistent account: $account");
    }

    $self->{'account'} = $account;

    return;
}

sub _AFTER_HEADERS ( $self, @ ) {
    my $server_obj = $self->get_server_obj();

    my $socket = $server_obj->connection->get_socket();

    Cpanel::Dsync::Stream::connect( $socket, $self->{'account'} );

    return;
}

1;
