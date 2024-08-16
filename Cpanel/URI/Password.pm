package Cpanel::URI::Password;

# cpanel - Cpanel/URI/Password.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::URI::Password

=head1 SYNOPSIS

    my $safe_uri = strip_password('http://user:password@host');

    my $pw = get_password('http://user:password@host');

=head1 DESCRIPTION

URI password-related utilities. Since authentication credentials in URIs are
categorically discouraged in the first place, hopefully this module is
only minimally needed!

=head1 FUNCTIONS

=cut

use cPstrict;

use Cpanel::LoadModule ();

my $HIDDEN_STR = '__HIDDEN__';

=head2 strip_password( URL_STRING )

Returns the URL_STRING, with any password in the URI replaced with the
string C<__HIDDEN__>.

=cut

#XXX Note that we don’t use() URI::Split because if we did that then
#updatenow.static’s make logic would complain about the non-core dependency.

sub strip_password ($url) {
    return unless defined $url;

    Cpanel::LoadModule::load_perl_module('URI::Split');

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split($url);

    if ( length $auth && $auth =~ s[(?<=:).+(?=@)][$HIDDEN_STR] ) {
        return URI::Split::uri_join( $scheme, $auth, $path, $query, $frag );
    }

    return $url;
}

=head2 get_password( URL_STRING )

Returns either undef or the password as in URL_STRING.

B<NOTE:> This does NOT URI-decode the password. That’s because the initial
need for this logic was to extract the password exactly as it shows in the
URL itself.

=cut

sub get_password ($url) {
    return unless defined $url;

    Cpanel::LoadModule::load_perl_module('URI::Split');

    my ( undef, $auth ) = URI::Split::uri_split($url);

    return unless defined $auth;

    $auth =~ m[(?<=:)(.+)(?=@)];

    return $1;
}

1;
