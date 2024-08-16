package Cpanel::JSON::HttpRequest;

# cpanel - Cpanel/JSON/HttpRequest.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Carp                     ();
use Cpanel::JSON             ();
use Cpanel::LoadModule       ();
use Cpanel::Locale           ();
use Cpanel::HttpRequest      ();    # PPI USE OK -  loaded below
use Cpanel::HttpRequest::SSL ();    # PPI USE OK -  loaded below

my $gl_locale;
my %singletons;

sub make_json_request {
    my ( $p_url, $p_content, %p_options ) = @_;

    # content submitted as POST or JSON? #
    my $submitas = $p_options{'submitas'} || 'JSON';

    # allow method override? #
    my $method = $p_options{'method'} || 'POST';

    # figure out protocol, host and port #
    Carp::croak "invalid request URL: $p_url"
      if $p_url !~ m/^(https?):\/\/([\w\d\.-]+)(:(\d+))?((\/.+?)(\?(.+))?)$/i;
    my $protocol = $1;
    my $host     = $2;
    my $port     = $4;
    my $uri      = $5;
    my $path     = $6;
    my $query    = $8;

    # convert data structure to JSON #
    Carp::croak 'content must be a HASHREF: ' . ref($p_content)
      if defined $p_content && ref $p_content ne ref {};

    my %http_args = (
        'hideOutput'         => 1,
        'http_retry_count'   => 1,
        'return_on_error'    => 1,
        'timeout'            => 150,
        'speed_test_enabled' => 0,
        'die_on_4xx_5xx'     => 1,
        'die_on_error'       => 1,     # for non-HTTP errors (e.g. connection timeouts)
    );

    # use the right protocol #
    my $module = 'Cpanel::HttpRequest';
    if ( $protocol eq 'https' ) {
        my %ssl_args = defined $p_options{'ssl_args'} ? %{ $p_options{'ssl_args'} } : ();
        @http_args{ keys %ssl_args } = values %ssl_args;
        $module = 'Cpanel::HttpRequest::SSL';
    }
    my $singleton_key = join( "___", $module, map { "$_=>$http_args{$_}" } sort keys %http_args );

    # Try to reuse the object so we can make persistant http requests
    my $req = $singletons{$singleton_key} ||= $module->new(%http_args);

    # request the proper locale #
    my $headers = defined $p_options{'headers'} ? $p_options{'headers'} : {};
    if ( !$headers->{'Accept-Language'} ) {
        $gl_locale ||= Cpanel::Locale->get_handle();
        my $lang_tag = $gl_locale->get_language_tag();
        if ( $lang_tag ne 'en' ) {

            # we still want a string, not a remote server failure due to non-localized #
            $headers->{'Accept-Language'} = "${lang_tag}, en;q=0.1";
        }
        else {
            $headers->{'Accept-Language'} = 'en';
        }
    }

    # make request #
    my ( $status, $response );

    eval {
        if ( $method eq 'GET' ) {
            ( $response, $status ) = $req->httpreq( $host, $uri, undef, 'port' => $port, 'headers' => $headers );
        }
        elsif ( $submitas eq 'POST' ) {
            ( $response, $status ) = $req->httppost( $host, $uri, $p_content, undef, 'port' => $port, 'headers' => $headers );
        }
        elsif ( $submitas eq 'JSON' ) {
            my $content_type = $headers->{'Content-Type'} || 'application/json';
            my $data;
            $data = Cpanel::JSON::Dump($p_content)
              if defined $p_content;
            ( $response, $status ) = $req->httpput( $host, $uri, $data, 'method' => $method, 'port' => $port, 'content_type' => $content_type, 'headers' => $headers );
        }
    };

    if ( my $exception = $@ ) {

        # If we detect an exception from Cpanel::HttpRequest that contains details about the error,
        # and the caller provided a more specific exception class to handle errors with JSON info,
        # feed the decoded data into that class and throw it. This provides enhanced error reporting
        # that has an awareness of the data structure the remote API uses for error reporting.
        if ( $exception->isa('Cpanel::Exception::HTTP::Server') ) {
            my $error_information = eval { Cpanel::JSON::Load( $exception->content ) };    # do not check $@; discard exception if this fails
            if ( 'HASH' eq ref $error_information && $p_options{json_exception_class} ) {
                Cpanel::LoadModule::load_perl_module('Cpanel::Exception');
                die Cpanel::Exception::create( $p_options{json_exception_class}, [ url => $exception->url, method => $exception->method, status => $exception->status, error_info => $error_information ] );
            }
        }

        # If either the exception was not a Cpanel::Exception::HTTP::Server at all, or it was but
        # lacked a valid JSON body, just go ahead and rethrow whatever we have.
        die $exception;
    }

    return undef, $req->{'last_status'}
      if !$status || !defined $response;
    die "non-JSON response came back from server: $response"
      if $response !~ m/^\{.+?\}$/ms;

    return Cpanel::JSON::Load($response), $req->{'last_status'};
}

1;
