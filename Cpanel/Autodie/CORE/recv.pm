package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/recv.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 recv()

cf. L<perlfunc/recv>

B<NOTE:> Cpanel::Autodie::recv_sigguard() is probably what you
want since that function retries on EINTR. (Also see CPAN L<IO::SigGuard>.)

=cut

our $_RECV_FAIL_EINTR;

sub recv_sigguard {    ## no critic(RequireArgUnpacking)
                       # $_[1]: buffer
    local ( $!, $^E );

    return CORE::recv( $_[0], $_[1], $_[2], $_[3] ) // goto FAIL;

  FAIL:

    goto &recv_sigguard if $! == _EINTR() && !$_RECV_FAIL_EINTR;

    my $err = $!;

    local $@;
    require Cpanel::Exception;

    # TODO: Maybe a different exception class would be useful, e.g.,
    # to include the flags?
    die Cpanel::Exception::create( 'IO::ReadError', [ error => $err, length => $_[2] ] );
}

=head2 sysread()

Like C<sysread_sigguard()> but without the retry on EINTR.

=cut

sub recv {
    local $_RECV_FAIL_EINTR = 1;
    return recv_sigguard(@_);
}

1;
