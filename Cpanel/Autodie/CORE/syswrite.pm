package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/syswrite.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 syswrite_sigguard()

Like C<syswrite()> below but will retry when EINTR is the failure,
much like the corresponding function in CPAN L<IO::SigGuard>.

You should probably always use this rather than C<syswrite()>.

=cut

our $_SYSWRITE_FAIL_EINTR;

sub syswrite_sigguard {    ## no critic(RequireArgUnpacking)
                           # $_[1]: buffer
    local ( $!, $^E );
    if ( $#_ == 3 ) {
        return CORE::syswrite( $_[0], $_[1], $_[2], $_[3] ) // goto FAIL;
    }
    elsif ( $#_ == 2 ) {
        return CORE::syswrite( $_[0], $_[1], $_[2] ) // goto FAIL;
    }
    else {
        return CORE::syswrite( $_[0], $_[1] ) // goto FAIL;
    }

  FAIL:
    goto &syswrite_sigguard if $! == _EINTR() && !$_SYSWRITE_FAIL_EINTR;

    my ( $length, $offset ) = @_[ 2 .. $#_ ];
    my $real_length = length $_[1];

    if ($offset) {
        if ( $offset > 0 ) {
            $real_length -= $offset;
        }
        else {
            $real_length = 0 - $offset;
        }
    }

    if ( defined $length && $length < $real_length ) {
        $real_length = $length;
    }

    my $err = $!;

    local $@;
    require Cpanel::Exception;

    die Cpanel::Exception::create( 'IO::WriteError', [ error => $err, length => $real_length ] );
}

=head2 syswrite()

Like C<syswrite_sigguard()> but without the retry on EINTR.

=cut

sub syswrite {
    local $_SYSWRITE_FAIL_EINTR = 1;
    return syswrite_sigguard(@_);
}

1;
