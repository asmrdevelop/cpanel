package Cpanel::Readlink;

# cpanel - Cpanel/Readlink.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie   ();
use Cpanel::Exception ();
use Cwd               ();

our $MAX_SYMLINK_DEPTH = 1024;

# provide a pure perl light implementation of Cwd::abs_path
sub deep {
    my ( $link, $provide_trailing_slash ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', 'Provide a link path.' ) if !length $link;

    # Trailing slashes will cause the path to be detected as a directory, not a symlink.
    # So recursively we'll strip them, resolve the symlink, then reattach one when we return (if needed).
    if ( length($link) > 1 && substr( $link, -1, 1 ) eq '/' ) {
        $link = substr( $link, 0, length($link) - 1 );
        return deep( $link, 1 );
    }

    # Most of the time this probably
    # isn't a link so lets stop here
    if ( !-l $link ) {
        return $provide_trailing_slash ? qq{$link/} : $link;
    }

    my %is_link;
    $is_link{$link} = 1;

    my $depth = 0;

    # initialize base
    my $base = _get_base_for($link);

    # make sure that base is absolute
    if ( substr( $link, 0, 1 ) ne '/' ) {
        $base = Cwd::abs_path() . '/' . $base;
    }

    while ( ( $is_link{$link} ||= -l $link ) && ++$depth <= $MAX_SYMLINK_DEPTH ) {
        $link = Cpanel::Autodie::readlink($link);
        if ( substr( $link, 0, 1 ) ne '/' ) {
            $link = $base . '/' . $link;
        }

        # always adjust base
        $base = _get_base_for($link);
    }

    return $provide_trailing_slash ? qq{$link/} : $link;
}

sub _get_base_for {
    my $basename = shift;
    my @path     = split( '/', $basename );
    pop(@path);
    return join( '/', @path );
}

1;
