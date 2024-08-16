package Cpanel::Pkgacct::Components::ApacheTLS;

# cpanel - Cpanel/Pkgacct/Components/ApacheTLS.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::ApacheTLS

=head1 SYNOPSIS

    my $obj = Cpanel::Pkgacct->new( ... );
    $obj->perform_component('ApacheTLS');

=head1 DESCRIPTION

This module exists to be called from L<Cpanel::Pkgacct>. It should not be
invoked directly except from that module.

It backs up the user’s Apache TLS installations.

=head1 METHODS

=cut

use strict;
use warnings;

use parent 'Cpanel::Pkgacct::Component';

use Try::Tiny;

use Cpanel::Config::userdata::Load ();
use Cpanel::Exception              ();
use Cpanel::FileUtils::Write       ();
use Cpanel::LoadModule             ();

=head2 I<OBJ>->perform()

This is just here to satisfy cplint. Don’t call this directly.

=cut

sub perform {
    my ($self) = @_;

    my $work_dir = $self->get_work_dir();

    my $is_root = !$>;
    if ($is_root) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Apache::TLS');
    }
    else {

        #It’s probably already loaded, but just for good measure:
        Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin::Call');
    }

    for my $vhost ( Cpanel::Config::userdata::Load::get_ssl_domains( $self->get_user() ) ) {
        my ( $key, $crt, @cab );

        try {
            if ($is_root) {
                ( $key, $crt, @cab ) = Cpanel::Apache::TLS->get_tls($vhost);
            }
            else {
                ( $key, $crt, @cab ) = Cpanel::AdminBin::Call::call( 'Cpanel', 'ssl_call', 'GET_KEY_AND_CERTIFICATES', $vhost );
            }

            #save the new way
            Cpanel::FileUtils::Write::overwrite(
                "$work_dir/apache_tls/$vhost",
                join( "\n", $key, $crt, @cab ),
            );

        }
        catch {
            $self->get_output_obj()->warn( "$vhost: " . Cpanel::Exception::get_string($_) );
        };
    }

    return 1;
}

1;
