package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/sysread.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 sysread()

cf. L<perlfunc/sysread>

B<NOTE:> Cpanel::Autodie::sysread_sigguard() is probably what you
want since that function retries on EINTR. (Also see CPAN L<IO::SigGuard>.)

=cut

our $_SYSREAD_FAIL_EINTR;

sub sysread_sigguard {    ## no critic(RequireArgUnpacking)
                          # $_[1]: buffer
    local ( $!, $^E );

    #NOTE: Perl's prototypes can throw errors on things like:
    #(@length_offset > 1) ? $offset : ()
    #...so the following writes out the two forms of sysread():

    if ( $#_ == 3 ) {
        return CORE::sysread( $_[0], $_[1], $_[2], $_[3] ) // goto FAIL;
    }
    else {
        return CORE::sysread( $_[0], $_[1], $_[2] ) // goto FAIL;
    }

  FAIL:

    #XXX: TODO: Accommodate negative $offset

    goto &sysread_sigguard if $! == _EINTR() && !$_SYSREAD_FAIL_EINTR;

    my $err = $!;

    local $@;
    require Cpanel::Exception;

    die Cpanel::Exception::create( 'IO::ReadError', [ error => $err, length => $_[2] ] );
}

=head2 sysread()

Like C<sysread_sigguard()> but without the retry on EINTR.

=cut

sub sysread {
    local $_SYSREAD_FAIL_EINTR = 1;
    return sysread_sigguard(@_);
}

1;
