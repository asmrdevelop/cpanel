package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/sysseek.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 sysseek()

cf. L<perlfunc/sysseek>

=cut

#----------------------------------------------------------------------
#NOTE: sysseek() and Cpanel::Autodie::seek() implementations are exactly the same except
#for the CORE:: function call.  Alas, Perl's prototyping stuff seems to
#make it impossible not to duplicate code here.

sub sysseek {
    my ( $fh, $pos, $whence ) = @_;

    local ( $!, $^E );
    return CORE::sysseek( $fh, $pos, $whence ) || do {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::FileSeekError', [ path => $fh, error => $err, whence => $whence, position => $pos ] );
    };
}

1;
