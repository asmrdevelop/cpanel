package Cpanel::HTTP;

# cpanel - Cpanel/HTTP.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LoadModule   ();
use Cpanel::Encoder::URI ();
use Cpanel::Time::HTTP   ();

my $EXPIRED_DATE = 'Thu, 01-Jan-1970 00:00:01 GMT';

#For testing
sub _get_expired_date {
    return $EXPIRED_DATE;
}

sub parse_accept_language {
    my $http_variable = shift || $ENV{'HTTP_ACCEPT_LANGUAGE'} || '';
    my @accepted      = map { $_->[1] }
      sort { $b->[0] <=> $a->[0] }
      map {
        m{[^\s;]}
          ? ( m{\A(.*);q=(.*)\z} ? [ $2, $1 ] : [ 1, $_ ] )    #cf. RFC2616 14.4
          : ()
      }
      split( m{\s*,\s*}, $http_variable );

    return wantarray ? @accepted : \@accepted;
}

#Determines the user's requested locales based on:
#1) "locale" GET parameter
#2) "session_locale" HTTP cookie
#3) HTTP_ACCEPT_LANGUAGE
#
#This does not validate the requested locales.
sub get_requested_locales {
    my @requested = (
        get_requested_session_locales(),
        parse_accept_language(),
    );

    return wantarray ? @requested : \@requested;
}

sub get_requested_session_locales {
    return (
        ( $ENV{'QUERY_STRING'} =~ m{(?:^|&)locale=([^&]+)} ? $1 : () ),
        { get_cookies() }->{'session_locale'} || (),
    );
}

sub parse_cookie_string {
    return {
        map   { $_ && tr{%+}{} ? Cpanel::Encoder::URI::uri_decode_str($_) : $_ }
          map { ( split( /=/, $_, 2 ) )[ 0, 1 ] }                                  #[0,1] e.g. secure=>undef
          split( /; /, shift || q{} )
    };
}

#parse HTTP_COOKIE, and cache
sub get_cookies {
    return %{ parse_cookie_string( shift || $ENV{'HTTP_COOKIE'} ) };
}

#name1, value1, {opts1}, name2, value2, {opts2}, etc.
#The opt "expired" is special: expired ? sets expired : not present
#The opt "insecure" is special: it avoids setting the 'secure' flag on the cookie even when HTTPS is on
#"expires", if it is all digits, is interpreted as a UNIX timestamp & converted
sub cookie_builder {
    my ( $cookie, $value, $opref );
    my $all_cookies = q{};
    my $ua          = $ENV{'HTTP_USER_AGENT'};
    if ( !exists $ENV{'HTTP_USER_AGENT'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp') if !$INC{'Cpanel/Carp.pm'};
        die Cpanel::Carp::safe_longmess("cookie_builder requires HTTP_USER_AGENT to be set");
    }

    while (@_) {
        ( $cookie, $value, $opref ) = splice( @_, 0, 3 );

        my @PARTS;
        my $insecure = 0;
        if ( ref $opref ) {
            foreach my $key ( sort keys %$opref ) {
                next if $key eq q{};
                if ( $key eq 'expired' ) {
                    if ( $opref->{$key} ) {
                        push @PARTS, "expires=$EXPIRED_DATE";
                    }
                }
                elsif ( $key eq 'insecure' ) {
                    $insecure = 1;
                }
                elsif ( lc $key eq 'expires' && defined $opref->{$key} && $opref->{$key} =~ m{\A\d+\z} ) {
                    push @PARTS, $key . '=' . Cpanel::Time::HTTP::time2cookie( $opref->{$key} );
                }
                else {
                    if ( defined $opref->{$key} ) {
                        push @PARTS, $key . '=' . $opref->{$key};
                    }
                    else {
                        push @PARTS, $key;
                    }
                }
            }
        }
        if ( $ENV{'HTTPS'} && $ENV{'HTTPS'} eq 'on' && !$insecure ) {
            push @PARTS, 'secure';
        }

        if ( $ENV{'SERVER_PORT'} ) {

            # browsers which do not support the port option in the cookie
            #  - safari + mac os x  [ case 47462 ]
            #       note that 'safari + windows' can understand the port option
            #  - playbook ( blackberry tablet ) [ case 49285 ]

            # ! ( safari + mac os x )
            # =~ !( $ua =~ m{Safari} && $ua =~ m{Mac OS X} && $ua !~ m{Chrome} )
            # =~ $ua =~ m{Chrome} || $ua !~ m{Safari} || $ua !~ m{Mac OS X}
            if ( ( index( $ua, 'Chrome' ) > -1 || index( $ua, 'Safari' ) > -1 || index( $ua, 'Mac OS X' ) == -1 ) && index( $ua, 'PlayBook' ) == -1 ) {
                push @PARTS, 'port=' . $ENV{'SERVER_PORT'};
            }
        }

        $all_cookies .= 'Set-Cookie: ' . join(
            '; ',
            Cpanel::Encoder::URI::uri_encode_str($cookie) . '=' . Cpanel::Encoder::URI::uri_encode_str($value),
            sort @PARTS    #sort so that we can test easily
        ) . "\r\n";
    }

    return $all_cookies;
}

my $http;

sub httpclient {
    if ( !$http ) {
        require Cpanel::HTTP::Tiny::FastSSLVerify;
        $http = Cpanel::HTTP::Tiny::FastSSLVerify->new();
    }
    return $http;
}

sub download_to_file {
    my ( $url, $file, $mirror ) = @_;

    die "download_to_file() requires a URL\n" if !length($url);

    if ( !length($file) ) {
        require File::Temp;
        my $fh = File::Temp->new( UNLINK => 0 );
        $file = $fh->filename;
    }

    my @args = ( $url, $file );

    # The "If-Modified-Since" header forces download and helps avoid 304’s that can result in an empty $file.
    if ( !$mirror ) {
        push @args, { headers => { "If-Modified-Since" => 1 } };
    }

    my $res = httpclient->mirror(@args);

    if ( !$res->{success} ) {
        die "Could not download “$url” to “$file”: " . join( ' ', map { $res->{$_} // '' } qw{ status reason } ) . "\n";
    }

    return $file;
}

1;

__END__

=encoding utf-8

=head1 FUNCTIONS

=head2 HTTP client related

=head3 httpclient

Takes no args.

Returns the appropriate-for-cPanel-code HTTP client; it is a singleton

=head3 download_to_file(URL)

Downloads given URL to a file.

Dies on failure. Returns the file path on success.

    my $tmpfile = download_to_file($url); # $url was just downloaded and saved to $tmpfile

The temp file does not get the same suffix as the URL. C<download_to_file()> could figure
out the extension but it gets complicated quickly (far more than rindex/substr the
ending dot-whatever) and would be wrong sometimes. So let the caller do what it
needs to (e.g. rename) since the caller knows.

You can additionally:

=over

=item pass a second argument to the file you want it download to instead of a random tmp file

    if (download_to_file($url, $localfile)) {  # $url was just downloaded and saved to $localfile

=item pass a third true argument that makes it behave as a mirror (as opposed to downloading it even if its the latest version)

    if (download_to_file($url, $localfile, 1)) {  # $url is at $localfile and was not updated if it was already the latest

=back

=head2 locale related

=head3 parse_accept_language

You probaby want C<get_requested_locales()> instead.

Takes a C<HTTP_ACCEPT_LANGUAGE> string (defaulting to the environment variable C<HTTP_ACCEPT_LANGUAGE> if not given) and
returns a list of languages it contains.

In scalar context returns an array ref of that list (I know I know, its gross).

=head3 get_requested_locales

Returns a list of locales built from:

=over

=item C<locale> GET parameter

via C<get_requested_session_locales()>

=item C<session_locale> HTTP cookie

via C<get_requested_session_locales()>

=item C<HTTP_ACCEPT_LANGUAGE>

via parse_accept_language()

=back

In scalar context returns an array ref of that list (I know I know, its gross).

=head3 get_requested_session_locales

You probaby want C<get_requested_locales()> instead.

Returns a list of locales built from:

=over

=item C<locale> GET parameter

=item C<session_locale> HTTP cookie

=back

=head2 cookie related

=head3 parse_cookie_string

Parses a given C<HTTP_COOKIE> string into a hashref.

=head3 get_cookies

Same as C<parse_cookie_string()> except is defaults to the environment variable C<HTTP_COOKIE>.

=head3 cookie_builder

Returns a string that are the HTTP C<Set-Cookie> headers based on arguments and the environment.

Its argments are very complex, see source/comments for details if you feel you need this.

