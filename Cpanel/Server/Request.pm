package Cpanel::Server::Request;

# cpanel - Cpanel/Server/Request.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Class::XSAccessor (
    getters => {
        get_start_time     => '_request_start_time',
        get_protocol       => '_protocol',
        get_request_method => '_request_method',

        # This is URI-decoded-then-reencoded and NOT appropriate for use
        # in filesystem lookups.
        get_uri                     => '_uri',
        get_supplied_security_token => '_supplied_security_token',
        get_headers                 => '_headers',

        # This is URI-decoded and appropriate to use in filesystem lookups.
        get_document       => '_document',
        get_request_line   => '_request_line',
        get_headers_string => '_headers_string',
        get_magic_revision => '_magic_revision',
    },
    setters => {
        set_protocol                => '_protocol',
        set_request_method          => '_request_method',
        set_uri                     => '_uri',
        set_supplied_security_token => '_supplied_security_token',
        set_headers                 => '_headers',
        set_error_output_type       => '_error_output_type',
        set_request_line            => '_request_line',
        set_headers_string          => '_headers_string',
        set_magic_revision          => '_magic_revision',
        _set_dnsadmin_only          => '_dnsadmin_only',
    }

);

use URI::XSEscape ();

use Cpanel::App          ();
use Cpanel::Encoder::URI ();
use Cpanel::Exception    ();
use Cpanel::HTTP         ();
use Cpanel::Session      ();
use parent 'Cpanel::Server::LogAccess';

########################################################
#
# Method:
#   new
#
# Description:
#   Creates a request object for a Cpanel::Server
#   object
#
# Parameters:
#   logs         - A Cpanel::Server::Logs object
#   (required)
#
# Returns:
#   A Cpanel::Server::Request object
#
sub new {
    my ( $class, %OPTS ) = @_;
    return bless {
        '_logs'               => ( $OPTS{'logs'} || die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'logs' ] ) ),
        '_request_start_time' => time(),
        '_protocol'           => '1.0',                                                                                            # speak http 1.0 by default
        '_dnsadmin_only'      => $OPTS{'dnsadmin_only'},
    }, $class;
}

sub start_new_request {
    delete @{ $_[0] }{ grep { $_ ne '_logs' && $_ ne '_dnsadmin_only' } keys %{ $_[0] } };
    $_[0]->set_protocol('1.0');
    $_[0]->{'_request_start_time'} = time();
    return 1;
}

sub get_cookies {
    $_[0]->_generate_cookies_from_headers() if !exists $_[0]->{'_cookies'};
    return $_[0]->{'_cookies'};
}

sub get_cookie {
    $_[0]->_generate_cookies_from_headers() if !exists $_[0]->{'_cookies'};
    return $_[0]->{'_cookies'}{ $_[1] };
}

sub _generate_cookies_from_headers {
    my ($self) = @_;

    if ( !exists $self->{'_headers'} ) {
        die "cookies are not available until a request has been made";
    }

    return ( $self->{'_cookies'} = Cpanel::HTTP::parse_cookie_string( $self->{'_headers'}{'cookie'} ) );
}

sub get_header {
    return $_[0]->{'_headers'}{ $_[1] };
}

sub delete_header {
    my ( $self, $header ) = @_;
    return delete $self->{'_headers'}{$header};
}

sub set_header {
    return ( $_[0]->{'_headers'}{ $_[1] } = $_[2] );
}

sub set_document {
    $_[0]->_set_dnsadmin_only(1) if $Cpanel::App::appname eq 'whostmgrd' && index( $_[1], 'scripts2/' ) > -1 && index( $_[1], '_local' ) > -1 && is_dns_cluster_request( $_[1] );
    return ( $_[0]->{'_document'} = $_[1] );
}

sub get_error_output_type {
    $_[0]->_determine_document_error_type() if !$_[0]->{'_error_output_type'};
    return $_[0]->{'_error_output_type'};
}

sub _determine_document_error_type {
    my ($self) = @_;
    my $document = $self->{'_document'};
    if ( index( $document, './cometd/' ) == 0 ) {
        $self->set_error_output_type('cometd');
    }
    elsif ( substr( $document, -4 ) eq '.ptt' || substr( $document, -6 ) eq '.phtml' ) {
        $self->set_error_output_type('partial-html');
    }
    elsif ( index( $document, '-api' ) > -1 && $document =~ m{/(json|xml)-api/} ) {
        $self->set_error_output_type($1);
    }
    elsif ( $document =~ m{^\./backend/passwordstrength.cgi$} ) {
        $self->set_error_output_type('json');
    }
    elsif ( $Cpanel::App::appname eq 'whostmgrd' && index( $document, 'scripts2/' ) > -1 && index( $document, '_local' ) > -1 && is_dns_cluster_request($document) ) {
        $self->set_error_output_type('dnsadmin');
    }
    else {
        $self->set_error_output_type('normal');
    }
    return 1;
}

sub is_dns_cluster_request {
    return 0 if $Cpanel::App::appname ne 'whostmgrd';    #dnsadmin requests should only be coming from whostmgrd
    my $doc = ref $_[0] ? $_[0]->{'_document'} : $_[0];
    return $doc =~ m/^\.\/scripts2\/+(?:getzone|getzones|getallzones|cleandns|getpath|getips|removezones|removezone|reloadbind|reconfigbind|quickzoneadd|savezone|synczones|synckeys|revokekeys|addzoneconf|getzonelist|zoneexists|reloadzones)_local/;
}

sub _uri_reencode_str {
    return Cpanel::Encoder::URI::uri_encode_str( Cpanel::Encoder::URI::uri_decode_str( $_[0] ) );
}

sub setup_request_from_rawuri {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $self, $uri ) = @_;

    # Split out query string.

    my $query_string = '';

    if ( index( $uri, '?' ) > -1 ) {
        ( $uri, $query_string ) = split( /\?/, $uri, 2 );

        # We need to decode and then re-encode QUERY_STRING.
        # We want all non-reserved (RFC 3986) characters to be encoded for security reasons.
        # We split apart the string on reserved characters, and then re-encode the rest.
        # See SEC-19 for further details.

        if (
            length $query_string

            # Skip encoding if the query string only contains very safe characters
            # very safe characters is $Cpanel::URI::Encoder::URI_SAFE_CHARS
            # and '=' and '&'
            && $query_string =~ tr{=&A-Za-z0-9\-_.!~*}{}c
        ) {
            $query_string =~ s/([^!*'();:@&=+\$,\/?#\[\]]+)/_uri_reencode_str($1)/ge;
        }
    }

    # Decode URI prior to additional processing.
    # Note that we do NOT decode “+” to space here because that’s
    # specifically for HTML form content submissions (i.e.,
    # application/x-www-form-urlencoded content).
    #
    if ( $uri =~ tr/%// ) {
        $uri = URI::XSEscape::uri_unescape($uri);
    }

    # Bail on CR/LF/NULL.

    if ( $uri =~ tr/\n\r\0// ) {
        die Cpanel::Exception->create("Documents are not permitted to contain null characters, or new lines.");
    }

    # Bail on core.

    if ( index( $uri, 'core' ) > -1 && ( $uri =~ /\.core$/ || $uri =~ /\/core\.\d+$/ || $uri =~ /\/core$/ ) && $uri !~ /xfer\w+\// ) {
        die Cpanel::Exception->create("Core file access denied.");
    }

    # Strip leading /'s

    substr( $uri, 0, 1, '' ) while index( $uri, '/' ) == 0;

    # Fold directory traversals.
    # Note: Attempted traversals past the root will be stripped.

    my @segments = split( '/', $uri, -1 );
    my @abs_segments;

    while ( defined( my $segment = shift @segments ) ) {
        if ( !length($segment) ) {
            if ( !@segments ) {

                # append the trailing empty segment
                push @abs_segments, $segment;
            }
            else {
                # drop the inner empty segment
            }
        }
        else {
            if ( $segment eq '..' ) {
                if (@abs_segments) {

                    # if a segment exists one level above, drop it and '..' segment
                    pop @abs_segments;
                }
            }
            elsif ( $segment eq '.' ) {

                # drop '.' segement
            }
            else {
                # append anything other non-special segments
                push @abs_segments, $segment;
            }
        }
    }

    # Grab security token

    my $supplied_security_token = '';

    if ( @abs_segments && ( index( $abs_segments[0], $Cpanel::Session::token_prefix ) == 0 ) && ( $abs_segments[0] !~ tr{A-Za-z0-9_}{}c ) ) {
        $supplied_security_token = '/' . shift(@abs_segments);
    }

    $self->set_supplied_security_token($supplied_security_token);

    # Grab magic_revision

    my $magic_revision = '';

    if ( @abs_segments && ( index( $abs_segments[0], 'cPanel_magic_revision_' ) == 0 ) && ( $abs_segments[0] !~ tr{A-Za-z0-9_}{}c ) ) {
        $magic_revision = shift(@abs_segments);
    }

    $self->set_magic_revision($magic_revision);

    # Generate final URI string.

    $uri = join( '/', @abs_segments );
    my $encoded_uri;
    if ( $uri =~ tr{A-Za-z0-9\-_\.~\/}{}c ) {    # If the uri contains chars that need to be encoded
        $encoded_uri = join( '/', map { $_ =~ tr{A-Za-z0-9\-_\.~\/}{}c ? URI::XSEscape::uri_escape($_) : $_ } @abs_segments );
    }
    else {
        $encoded_uri = $uri;
    }

    # Set request and environment variables.
    # Per historical cPanel convention, only the document is fully decoded.
    # The remaining variables stay encoded.

    $self->set_uri($encoded_uri);

    $self->set_document( './' . $uri );

    $ENV{'QUERY_STRING'} = $query_string;

    my $script_uri = $supplied_security_token . ( length $magic_revision ? "/$magic_revision" : '' ) . "/$encoded_uri";
    $ENV{'SCRIPT_URI'}  = $script_uri;
    $ENV{'REQUEST_URI'} = $script_uri . ( length $query_string ? "?$query_string" : '' );

    return 1;
}

sub check_magic_revision {
    return 1 if length $_[0]->{'_magic_revision'};
    return 0;
}

1;
