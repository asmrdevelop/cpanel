package Cpanel::Template::Plugin::Count;

# cpanel - Cpanel/Template/Plugin/Count.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base 'Template::Plugin';

sub new {
    my ( $class, $context, $start ) = @_;
    my $count = count($start);
    return $count;
}

sub count {
    my $count = shift || 1;
    return sub {
        return $count++;
    };
}

1;
