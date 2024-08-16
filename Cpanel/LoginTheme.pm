package Cpanel::LoginTheme;

# cpanel - Cpanel/LoginTheme.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::StringFunc::Trim ();
use Cpanel::Encoder::URI     ();
use Cpanel::HTTP             ();

#a hard-coded default
my $DEFAULT_LOGIN_THEME = 'cpanel';

our $DOCROOT = '/usr/local/cpanel/base';

our $VERSION = '2.0';

sub getloginfile {
    my ( $url, $docroot ) = _get_login_url(@_);
    return $url ? ( $docroot . $url ) : ();
}

sub get_login_url {
    return if !length $_[0];

    my ( $basename, $ext ) = $_[0] =~ m{\A(.*)(?:\.([^.]+))\z};

    return (
        _get_login_url(
            docname                => length $basename ? $basename : $_[0],
            docext                 => length $ext      ? $ext      : q{},
            logintheme             => scalar get_login_theme(),
            check_default          => 1,
            allow_slash_in_docname => 1,
        )
    )[0];
}

# NOTE: We effectively append "/unprotected" to the given docroot.
sub _get_login_url {
    my %OPTS = @_;
    unless ( $OPTS{'allow_slash_in_docname'} ) {
        foreach my $k (qw{appname logintheme docext docname}) {
            $OPTS{$k} =~ tr{/}{}d if defined $OPTS{$k};
        }
    }
    my $docroot    = $OPTS{'docroot'}    || $DOCROOT;
    my $logintheme = $OPTS{'logintheme'} || '';
    my $appname    = $OPTS{'appname'}    || '';

    my $docext = $OPTS{'docext'} || '';
    $docext = ".$docext" if length $docext;

    my $docname = $OPTS{'docname'};
    chop($docname) if substr( $docname, -1 ) eq '/';

    for (

        #example: unprotected/shanna/header_cpaneld.html
        ( $appname ? "/unprotected/$logintheme/${docname}_${appname}$docext" : () ),

        #example: unprotected/shanna/header.html
        "/unprotected/$logintheme/$docname$docext",

        #example: unprotected/header_cpaneld.html
        ( $appname ? "/unprotected/${docname}_${appname}$docext" : () ),

        #example: unprotected/header.html
        "/unprotected/$docname$docext",
    ) {
        tr{/}{}s;
        return ( $_, $docroot ) if -e ( $docroot . $_ );    # All files in unprotected should be 0644
    }

    return;
}

my $_cached_login_theme;

sub get_login_theme {

    # Order of preference (a bad theme will always result in usage of the default theme):
    # 1. module's internal cache
    # 2. theme specified as part of the query string
    # 3. theme stored in user's "session_login_theme" cookie
    # 4. theme specified as the global server default
    # 5. default theme provided by cPanel

    return $_cached_login_theme if $_cached_login_theme;

    my $theme;
    my $cpconf_ref;

    $theme = get_query_login_theme();
    if ( !$theme ) {
        my $cookies_hr = %main::Cookies ? \%main::Cookies : { Cpanel::HTTP::get_cookies() };
        $theme = normalize_and_validate_login_theme( $cookies_hr->{'login_theme'} );

        if ( !$theme ) {
            require Cpanel::Config::LoadCpConf;
            $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
            $theme      = $cpconf_ref->{'default_login_theme'};
        }
    }

    if ( !$theme ) {
        $theme = $DEFAULT_LOGIN_THEME;
    }

    # Make sure the theme exists if it's not $DEFAULT_LOGIN_THEME.
    # This includes checking a custom server login theme, so we
    # guarantee that a login theme is always available.
    elsif ( $theme ne $DEFAULT_LOGIN_THEME ) {
        if ( !-d $DOCROOT . "/unprotected/$theme" ) {
            $theme = $DEFAULT_LOGIN_THEME;
        }
    }

    return $_cached_login_theme = $ENV{'LOGIN_THEME'} = $theme;
}

sub normalize_and_validate_login_theme {
    my $theme = $_[0];

    if ( defined $theme ) {
        return if $theme =~ tr{/}{};    #Theme names can't have slashes.

        return if $theme !~ tr{ \r\n\t}{}c;    #sanity

        Cpanel::StringFunc::Trim::ws_trim( \$theme );

        $theme =~ tr{\r\n}{}d;

        return if index( $theme, '..' ) > -1;    #No double dots.
        return if $theme =~ tr{;:=}{};           #No ;, : =
        return if $theme eq '0';                 #Might as well make this explicit.
    }

    return $theme;
}

sub get_query_login_theme {
    if ( ( shift || $ENV{'QUERY_STRING'} || q{} ) =~ m{(?:^|&)login_theme=([^&]+)} ) {
        my $theme = $1;
        if ( $theme =~ tr{%+}{} ) {
            $theme = Cpanel::Encoder::URI::uri_decode_str($theme);
        }
        return normalize_and_validate_login_theme($theme);
    }
    return;
}

1;
