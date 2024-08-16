package Cpanel::Path::Safety;

# cpanel - Cpanel/Path/Safety.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub make_safe_for_path {
    my $param    = shift;
    my $refparam = $param;

    if ( !ref $param ) {
        $refparam = \$param;
    }

    $$refparam =~ tr{\0}{}d;
    $$refparam =~ s/(\/)(?:\.\.\/)+/$1/g;
    $$refparam =~ s/^..\///;

    return $$refparam;
}

sub safe_in_path {
    my $param = shift;

    if ( $param =~ m/^\s*$/ ) {
        return;
    }

    my $safe_param = make_safe_for_path($param);
    return $param eq $safe_param;
}

#
# Tokenize a path into list elements, removing superfluous dots.  An empty
# element is left at the beginning of the list when an absolute path is
# provided.
#
sub safe_get_path_components {
    my ($path) = @_;
    my @components = split( /\//, $path );

    my @ret = grep { $_ && $_ ne '.' } @components;

    return $components[0] ? @ret : ( '', @ret );
}

1;
