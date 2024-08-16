package Cpanel::Template::Plugin::Cycle;

# cpanel - Cpanel/Template/Plugin/Cycle.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base 'Template::Plugin';

sub new {
    my ( $class, $context, @list ) = @_;

    my $cycle = cycle(@list);
    return $cycle;
}

sub cycle {
    my @list = @_;
    return sub {
        my ( $first, @rest ) = @list;
        @list = ( @rest, $first );
        return $first;
    };
}

1;
