package Cpanel::SPF::Test;

# cpanel - Cpanel/SPF/Test.pm                      Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SPF::Test

=head1 SYNOPSIS

    my @missing = Cpanel::SPF::Test::find_missing_includes(
        'v=spf1 a mx +include:haha.com -all',
        'haha.com',
    );

=head1 DESCRIPTION

This module contains logic for testing SPF strings.

=head1 FUNCTIONS

=head2 @missing_hosts = find_missing_includes( $SPF, @HOSTS )

Returns the members of @HOSTS that are not whitelisted via C<include>
in $SPF. (In scalar context this returns the number of such hosts.)

Right now this doesn’t accommodate macros; we may need to beef up the
logic in the future.

=cut

use strict;
use warnings;

sub find_missing_includes {
    my ( $spf, @hosts ) = @_;

    my @expected_includes = map { "include:$_" } @hosts;

    my %parts = map { tr{+}{}dr => 1 } split( m{\s+}, $spf );

    my @missing = grep { !$parts{$_} } @expected_includes;

    substr( $_, 0, 8 ) = q<> for @missing;

    return @missing;
}

1;
