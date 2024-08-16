package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/systell.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie::CORE::sysseek ();    # PPI NO PARSE

=encoding utf-8

=head1 FUNCTIONS

=head2 systell()

Like C<tell()> but gives the filehandle’s true offset.
(Similar to the relationship between C<seek()> and C<sysseek()>.)

=cut

#Note that, since we die() on error, this does NOT return "0 but true"
#as sysseek() does; instead it returns just a plain 0.
sub systell {
    my ($fh) = @_;

    #cf. perldoc -f tell
    return 0 + Cpanel::Autodie::sysseek( $fh, 0, 1 );
}

1;
