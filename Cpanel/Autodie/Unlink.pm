package Cpanel::Autodie::Unlink;

# cpanel - Cpanel/Autodie/Unlink.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Autodie ('unlink_if_exists');

*unlink_if_exists = *Cpanel::Autodie::unlink_if_exists;

#Unlinks a group of files, suppressing errors until all attempted unlinks
#are completed. If any of the paths exists but fails to be unlink()ed, we
#an exception is thrown. If more than one path fails in this matter, we throw
#an exception collection--one exception per failure.
#
#On success, this returns the number of existent paths unlinked.
#
sub unlink_if_exists_batch {
    my @paths = @_;

    my ( $unlinked, @errs );

    while (@paths) {
        try {
            while ( my $p = shift @paths ) {
                $unlinked += unlink_if_exists($p);
            }
        }
        catch {
            push @errs, $_;
        };
    }

    if (@errs) {
        if ( @errs > 1 ) {
            local $@;
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'Collection', [ exceptions => \@errs ] );
        }

        die $errs[0];
    }

    return $unlinked;
}

1;
