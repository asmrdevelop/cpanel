package Cpanel::NetCurlEasy;

# cpanel - Cpanel/NetCurlEasy.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::NetCurlEasy

=head1 SYNOPSIS

    my $easy = Cpanel::NetCurlEasy::create_simple('http://the.site/main.css');

    Cpanel::NetCurlEasy::set_request_headers($easy, Accept => 'text/css' );

=head1 DESCRIPTION

This module implements certain conveniences around
L<Net::Curl::Easy> instances.

=cut

#----------------------------------------------------------------------

use Net::Curl::Easy ();

# For mocking in tests
our $_CURLOPT_UNIX_SOCKET_PATH_CR = Net::Curl::Easy->can('CURLOPT_UNIX_SOCKET_PATH');

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $easy_obj = create_simple($URL)

Creates a L<Net::Curl::Easy> instance with $URL as its URL.
Response header and body will be written to $easy_obj’s C<head> and
C<body> internal properties.

=cut

sub create_simple ($url) {
    my $easy_obj = Net::Curl::Easy->new();

    $easy_obj->setopt( Net::Curl::Easy::CURLOPT_URL, $url );

    $_ = q<> for @{$easy_obj}{ 'head', 'body' };

    $easy_obj->setopt( Net::Curl::Easy::CURLOPT_HEADERDATA, \$easy_obj->{head} );

    $easy_obj->setopt( Net::Curl::Easy::CURLOPT_FILE, \$easy_obj->{body} );

    return $easy_obj;
}

=head2 set_request_headers($EASY_OBJ, @KEY_VALUES)

Adds or removes one or more headers in $EASY_OBJ.
To remove a header, set its value as undef.

=cut

sub set_request_headers ( $easy_obj, @key_values ) {
    die "Uneven key/value list given!" if @key_values % 2;

    my @header_strs;
    while ( my ( $key, $value ) = splice @key_values, 0, 2 ) {
        $value = defined($value) ? " $value" : q<>;

        push @header_strs, "$key:$value";
    }

    $easy_obj->pushopt( Net::Curl::Easy::CURLOPT_HTTPHEADER => \@header_strs );

    return;
}

=head2 set_form_post($EASY_OBJ, \%ARGS)

Sets $EASY_OBJ to make an HTTP POST, with the values from %ARGS as
the form-encoded (i.e., C<application/x-www-form-urlencoded>) payload.

=cut

sub set_form_post ( $easy_obj, $opts_hr ) {

    local ( $@, $! );
    require Cpanel::HTTP::QueryString;

    my $payload = Cpanel::HTTP::QueryString::make_query_string($opts_hr);

    $easy_obj->setopt( Net::Curl::Easy::CURLOPT_POSTFIELDSIZE  => length $payload );
    $easy_obj->setopt( Net::Curl::Easy::CURLOPT_COPYPOSTFIELDS => $payload );

    return;
}

#----------------------------------------------------------------------

# This fixes the following problem:
#
#   Example:
#       1) Perl opens FD 41, gives it to curl.
#       2) curl closes FD 41.
#       3) Unbound opens FD 41.
#       4) Perl closes FD 41, which breaks Unbound.
#
# By preventing Perl from reaping its filehandle, we prevent
# closure of the file descriptor.
#
# (CPAN’s IO::FDSaver also addresses this problem.)
#
sub _immortalize_fd ($fh) {

    local ( $@, $! );
    require POSIX;
    return POSIX::dup( fileno $fh );
}

=head2 set_unix_socket_path($EASY_OBJ, $PATH)

Sets a unix socket that $EASY_OBJ will use to make its request.
This accommodates curls that lack native unix socket support.

=cut

sub set_unix_socket_path ( $easy_obj, $path ) {
    if ($_CURLOPT_UNIX_SOCKET_PATH_CR) {
        $easy_obj->setopt( $_CURLOPT_UNIX_SOCKET_PATH_CR->() => $path );
    }
    else {

        # CloudLinux 6’s libcurl doesn’t support unix sockets directly,
        # but we can achieve the same effect thus:
        $easy_obj->setopt(
            Net::Curl::Easy::CURLOPT_OPENSOCKETFUNCTION => sub ( $easy, $, $addr_hr, @ ) {

                local ( $@, $! );
                require Socket;
                require Cpanel::Autodie;

                @{$addr_hr}{ 'family', 'protocol', 'addr' } = (
                    Socket::AF_UNIX(),
                    0,
                    Socket::pack_sockaddr_un($path),
                );

                my $socket;
                my $ok = eval { Cpanel::Autodie::socket( $socket, @{$addr_hr}{ 'family', 'socktype', 'protocol' } ); };

                if ( !$ok ) {
                    warn;
                    return Net::Curl::Easy::CURL_SOCKET_BAD;
                }

                my $dupfd = _immortalize_fd($socket) // do {
                    warn "POSIX::dup(): $!";
                    return Net::Curl::Easy::CURL_SOCKET_BAD;
                };

                return $dupfd;
            },
        );
    }

    return;
}

=head2 $supported_yn = set_socket_if_supported($EASY_OBJ, $SOCKET)

Sets $SOCKET as the socket that $EASY_OBJ will use. Stores a reference
to $SOCKET in $EASY_OBJ to prevent Perl from C<close()>ing the socket.

This doesn’t work in older curls. With such curls this function is
a no-op and returns falsy; otherwise, a truthy value is returned.

=cut

sub set_socket_if_supported ( $curl_easy, $socket ) {
    my $supported_yn;

    # CloudLinux 6’s curl (7.19) can’t do this.
    if ( my $cr = Net::Curl::Easy->can('CURL_SOCKOPT_ALREADY_CONNECTED') ) {

        # Store a reference to the socket so that Perl won’t close it
        # while we still need it.
        $curl_easy->{'_socketfd'} = _immortalize_fd($socket) // do {
            die "POSIX::dup(): $!";
        };

        $curl_easy->setopt(
            Net::Curl::Easy::CURLOPT_OPENSOCKETFUNCTION,
            \&_easy_get_socketfd,
        );

        $curl_easy->setopt(
            Net::Curl::Easy::CURLOPT_SOCKOPTFUNCTION,
            $cr,
        );

        $supported_yn = 1;
    }

    return $supported_yn || 0;
}

sub _easy_get_socketfd ( $easy, @ ) {
    return $easy->{'_socketfd'};
}

1;
