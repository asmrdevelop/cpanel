package Cpanel::Locale::Utils::Fallback;

# cpanel - Cpanel/Locale/Utils/Fallback.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Locale::Utils::Fallback

=head1 DESCRIPTION

This module contains fallback logic for when L<Cpanel::Locale> fails
to load.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 interpolate_variables( $STRING, @VARIABLES )

Attempts to interpolate @VARIABLES into $STRING as make<Z<>text variables.

The interpolation logic is much simpler than the “real” C<makeZ<>text()>
and may not always be pretty, but it’s more helpful than not
doing any interpolation.

=cut

sub interpolate_variables {
    my ( $str, @maketext_opts ) = @_;

    # when we cannot localize do our best to provide a visible message
    my $c = 1;
    my %h = map { $c++, $_ } @maketext_opts;
    $str =~ s{(\[(?:[^_]+,)?_([0-9])+\])}{$h{$2}}g;
    return $str;
}

1;
