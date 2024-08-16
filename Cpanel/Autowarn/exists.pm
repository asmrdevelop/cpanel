package Cpanel::Autowarn;

# cpanel - Cpanel/Autowarn/exists.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Autowarn::exists

=head1 SYNOPSIS

    use Cpanel::Autowarn ();

    Cpanel::Autowarn::exists($path) or do {

        # When $path can’t be confirmed to exist …

    };

=head1 FUNCTIONS

=head2 $looks_ok = exists( $PATH )

Like Perl’s built-in C<-e>, but:

=over

=item * This will C<warn()> on any error response other than ENOENT.

=item * This returns !!0 for ENOENT and undef for other error responses.

=back

=cut

sub exists {
    local ( $!, $^E );

    return -e $_[0] || do {
        if ( $! == _ENOENT() ) {
            !!0;
        }
        else {
            warn "stat($_[0]): $!";
            undef;
        }
    };
}

1;
