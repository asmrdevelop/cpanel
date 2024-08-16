package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/select.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 select()

cf. L<perlfunc/select>

=cut

sub select {    ##no critic qw(RequireArgUnpacking)
    my ( $rbits_r, $wbits_r, $ebits_r, $timeout ) = ( \$_[0], \$_[1], \$_[2], $_[3] );

    #Perl::Critic says not to use one-arg select() anyway.
    die "Need four args!" if @_ < 4;

    local ( $!, $^E );
    my ( $nfound, $timeleft ) = CORE::select( $$rbits_r, $$wbits_r, $$ebits_r, $timeout );

    if ( $nfound == -1 ) {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::SelectError', [ error => $err ] );
    }

    return wantarray ? ( $nfound, $timeleft ) : $nfound;
}

1;
