package Cpanel::Cookies;

# cpanel - Cpanel/Cookies.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

$Cpanel::Cookies::VERSION = '0.1';

sub get_cookie_hashref_from_string {
    return {} if !defined $_[0];
    return {
        map {
            map {
                s/%([a-fA-F0-9][a-fA-F0-9])/pack('C', hex($1))/eg if -1 != index( $_, '%' );
                $_;
            } split m<=>, $_, 2
        } split( /; /, $_[0] )
    };
}

my $http_cookie_cached;

sub get_cookie_hashref {

    # no need to check $ENV{'HTTP_COOKIE'} for existence or definedness
    # let the caller decide to warn/set default/etc if that is important
    if ( !defined $http_cookie_cached ) {
        $http_cookie_cached = get_cookie_hashref_from_string( $ENV{'HTTP_COOKIE'} );
    }

    return $http_cookie_cached;
}

sub get_cookie_hashref_recache {

    # no need to check $ENV{'HTTP_COOKIE'} for existence or definedness
    # let the caller decide to warn/set default/etc if that is important
    $http_cookie_cached = get_cookie_hashref_from_string( $ENV{'HTTP_COOKIE'} );
    return $http_cookie_cached;
}

1;

__END__

=head1 Consistent, reusable cookie hash builder w/ caching

=head2 get_cookie_hashref()

Returns a cached cookie hashref built out of $ENV{'HTTP_COOKIE'}

=head2 get_cookie_hashref_recache()

Re-build the cached cookie hashref out of $ENV{'HTTP_COOKIE'} and return the new hashref.

=head2 get_cookie_hashref_from_string( $HTTP_COOKIE_STRING );

Parses the given string into a cookie hashref and returns said hashref.
