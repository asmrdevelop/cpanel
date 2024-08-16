package Cpanel::Version;

# cpanel - Cpanel/Version.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Version::Full ();

our ( $VERSION, $MAJORVERSION, $LTS ) = ( '4.0', '11.120', '11.120' );

# 11.29.0 (build 1)
sub get_version_text {
    return sprintf( "%d.%d (build %d)", ( split( m{\.}, Cpanel::Version::Full::getversion() ) )[ 1, 2, 3 ] );
}

sub get_version_parent {
    return _ver_key('parent_version');
}

# 65.0.1
sub get_version_display {
    return sprintf( "%d.%d.%d", ( split( m{\.}, Cpanel::Version::Full::getversion() ) )[ 1, 2, 3 ] );
}

# 11.29.0.1
{
    no warnings 'once';    # for updatenow
    *get_version_full = *Cpanel::Version::Full::getversion;
}

# 11.29.0
sub getversionnumber {
    return sprintf( "%d.%d.%d", ( split( m{\.}, Cpanel::Version::Full::getversion() ) )[ 0, 1, 2 ] );
}

sub get_lts {
    return $LTS;
}

sub get_short_release_number {
    my $current_ver = ( split( m{\.}, Cpanel::Version::Full::getversion() ) )[1];
    if ( $current_ver % 2 == 0 ) {
        return $current_ver;
    }
    return $current_ver + 1;
}

sub _ver_key {
    require Cpanel::Version::Tiny if !$INC{'Cpanel/Version/Tiny.pm'};
    return ${ $Cpanel::Version::Tiny::{ $_[0] } };
}

sub compare {
    require Cpanel::Version::Compare;
    goto &Cpanel::Version::Compare::compare;
}

# If $major is even, rounds up $ver and determines if they match.  Otherwise,
# determines if they are the same major version.  Essentially, determines
# whether a tag for $ver should be built when $MAJORVERSION is $major.
sub is_major_version {
    my ( $ver, $major ) = @_;

    require Cpanel::Version::Compare;

    return ( $ver eq $major || Cpanel::Version::Compare::get_major_release($ver) eq $major ) ? 1 : 0;
}

sub is_development_version {
    return substr( $MAJORVERSION, -1 ) % 2 ? 1 : 0;
}

# Format a version number for display.
sub display_version {
    my ($ver) = @_;
    if ( defined $ver && $ver =~ tr{\.}{} >= 2 ) {
        my @v = split( m{\.}, $ver );
        if ( $v[0] == 11 && $v[1] >= 54 ) {
            return join( '.', (@v)[ 1, 2, 3 ] );
        }
        return $ver;
    }
    return;
}

1;
