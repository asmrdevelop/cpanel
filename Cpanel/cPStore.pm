package Cpanel::cPStore;

# cpanel - Cpanel/cPStore.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::cPStore - cPanel Store client

=head1 SYNOPSIS

    use Cpanel::cPStore ();

    #This will validate the login token and retrieve an API token
    #before returning.
    my $api_token = Cpanel::Store::validate_login_token('..')->{'token'};

    my $cps = Cpanel::cPStore->new( api_token => $api_token );

    #an unauthenticated client; only has access to public data
    my $cps2 = Cpanel::cPStore->new();

    #The following will all return the “data” and discard the “message”:
    my $get = $cps->get( $endpoint );
    my $delete = $cps->delete( $endpoint );
    my $post = $cps->post( $endpoint, key => value, ... );
    my $put = $cps->put( $endpoint, key => value, ... );

=head1 DESCRIPTION

All methods will throw exceptions on errors. This includes API failures,
which are reported via the C<Cpanel::Exception::cPStoreError> class. Actual
network failures or other kinds of problems, of course, will be reported via
other appropriate exception types.

=cut

use strict;
use warnings;

use Try::Tiny;

use Digest::SHA ();

use Cpanel::Config::Sources ();
use Cpanel::LoadModule      ();
use Cpanel::cPStore::Utils  ();
use Cpanel::Exception       ();
use Cpanel::HTTP::Client    ();
use Cpanel::JSON            ();

our $TIMEOUT = 90;

my @DEFAULT_HEADERS = (
    'Content-Type' => 'application/vnd.cpanel.store-v1+json',
);

#static
sub LOGIN_URI {
    my ($url_after_login) = @_;

    die "Need after-login URL!" if !$url_after_login;

    my $login_uri_base = Cpanel::Config::Sources::get_source('TICKETS_SERVER_URL') . '/oauth2/auth/login';

    my @emails = ();

    if ($>) {
        my $username = getpwuid $> or die "No username found for EUID $>";

        require Cpanel::Config::LoadCpUserFile;
        @emails = Cpanel::Config::LoadCpUserFile::load($username)->contact_emails_ar()->@*;
    }
    else {
        Cpanel::LoadModule::load_perl_module('Cpanel::Config::LoadWwwAcctConf');
        my $wwwconfig = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
        push @emails, $wwwconfig->{'CONTACTEMAIL'};
    }

    return "$login_uri_base?" . Cpanel::HTTP::Client->www_form_urlencode(
        {
            redirect_uri  => $url_after_login,
            response_type => 'token',
            client_id     => _CLIENT_ID(),
            email         => $emails[0] || '',
        }
    );
}

sub CHECKOUT_URI {
    my ($order_id) = @_;

    return Cpanel::Config::Sources::get_source('STORE_SERVER_URL') . '/checkout/ssl/' . $order_id;
}

sub CHECKOUT_URI_WHM {
    my ($order_id) = @_;

    return Cpanel::Config::Sources::get_source('STORE_SERVER_URL') . '/checkout/whm/' . $order_id;
}

#Returns a hashref of the result of the OAuth2 validate_token call,
#which looks thus:
#
#   {
#       refresh_token => '..',
#       token => '..',
#   }
#
sub validate_login_token {
    my ( $token, $url_after_login ) = @_;

    die "Need token!"           if !$token;
    die "Need after-login URL!" if !$url_after_login;

    return Cpanel::cPStore::Utils::validate_authn(
        'validate_token',
        {
            code         => $token,
            redirect_uri => $url_after_login,
            client_id    => _CLIENT_ID(),
        },
    );
}

sub _CLIENT_ID {

    # This should be compiled in to every binary where this module is used
    die q[_CLIENT_ID called from uncompiled code] unless $INC{'Cpanel/CpKeyClt/SysId.pm'};

    # A 128-character string...
    return Digest::SHA::sha512_hex( 'Cpanel::CpKeyClt::SysId'->can('getsysid')->() );
}

#----------------------------------------------------------------------
# OO interface

#Accepts:
#   api_token (optional)
#
sub new {
    my ( $class, %opts ) = @_;

    my %default_headers = @DEFAULT_HEADERS;
    my $self            = bless {
        _http => Cpanel::HTTP::Client->new(
            default_headers => \%default_headers,
            timeout         => $TIMEOUT,
        )
    }, $class;

    $self->set_api_token( $opts{'api_token'} ) if $opts{'api_token'};

    $self->{'_http'}->die_on_http_error();

    return bless $self, $class;
}

sub set_api_token {
    my ( $self, $api_token ) = @_;

    if ( length $api_token ) {
        $self->{'_http'}->set_default_header( 'Authorization', "Bearer $api_token" );
    }
    else {
        $self->{'_http'}->delete_default_header('Authorization');
    }
    $self->{'_api_token'} = $api_token;

    return 1;

}

sub api_token {
    my ($self) = @_;
    return $self->{'_api_token'};
}

#@payload_dict is just a list of key/value pairs
sub post {
    my ( $self, $endpoint, @payload_dict ) = @_;

    return $self->_request( 'post', $endpoint, @payload_dict );
}

sub get {
    my ( $self, $endpoint ) = @_;

    #convenience for developers
    die "GET requests don’t send data!" if @_ > 2;

    return $self->_request( 'get', $endpoint );
}

#@payload_dict is just a list of key/value pairs
sub put {
    my ( $self, $endpoint, @payload_dict ) = @_;

    return $self->_request( 'put', $endpoint, @payload_dict );
}

sub delete {
    my ( $self, $endpoint ) = @_;

    #convenience for developers
    die "DELETE requests don’t send data!" if @_ > 2;

    return $self->_request( 'delete', $endpoint );
}

sub _request {
    my ( $self, $method, $endpoint, %form ) = @_;

    my $resp;
    try {
        $resp = $self->{'_http'}->$method(
            Cpanel::Config::Sources::get_source('STORE_SERVER_URL') . '/json-api/' . $endpoint,
            ( %form ? { content => Cpanel::JSON::Dump( \%form ) } : () ),
        );
    }
    catch {
        my $parse = try { $_->isa('Cpanel::Exception::HTTP::Server') };
        $parse &&= try { Cpanel::cPStore::Utils::unpack_api_response_content( $_->get('content') ) };

        if ($parse) {
            my $type = $parse->{'error'};
            if ($type) {
                my $method_uc = $method =~ tr<a-z><A-Z>r;

                die Cpanel::Exception::create(
                    'cPStoreError',
                    {
                        request => "$method_uc $endpoint",
                        type    => $type,
                        message => $parse->{'message'},
                        data    => $parse->{'data'},
                    },
                );
            }
        }

        local $@ = $_;
        die;
    };

    return Cpanel::cPStore::Utils::unpack_api_response_content( $resp->content() )->{'data'};
}

1;
