package Cpanel::Autowarn;

# cpanel - Cpanel/Autowarn/unlink.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Autowarn::unlink

=head1 SYNOPSIS

    use Cpanel::Autowarn ();

    Cpanel::Autowarn::unlink($path) or do {

        # When there is no $path to unlink …

    };

=head1 FUNCTIONS

=head2 $ok = unlink( $PATH )

Like Perl’s built-in, but this will C<warn()> on any error response
other than ENOENT.

This only accepts 0 or 1 parameters; an exception is thrown if
this function receives more than 1 parameter. This is to avoid
the partial-success states that can result from passing multiple
parameters to the C<unlink()> built-in.

=cut

sub unlink {    ## no critic qw( RequireArgUnpacking )
    die "At most 1 parameter!" if @_ > 1;

    local ( $!, $^E );

    my $path = @_ ? $_[0] : $_;
    my $ret  = _unlink($path);

    if ( $! && $! != _ENOENT() ) {
        warn "unlink($path): $!";
    }

    return $ret;
}

# mocked in tests
sub _unlink { return CORE::unlink( $_[0] ) }

1;
