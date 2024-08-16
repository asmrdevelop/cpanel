package Cpanel::ForcePassword::Check;

# cpanel - Cpanel/ForcePassword/Check.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# Very important that this method remain synchronized with Cpanel::ForcePassword::need_password_change
# This is effectively a fast, simplified version of that method.
sub need_password_change {
    my ( $user, $homedir ) = @_;
    my $file = "$homedir/.cpanel/passwordforce";
    return unless -f $file;

    # Contains a small percentage chance of a race condition with an update.
    # Decision was to accept risk for speed.
    open my $fh, '<', $file or return;
    my $match = $user . $/;
    while (<$fh>) {
        next if $match gt $_;
        return $match eq $_;
    }
    return;
}

1;    # Magic true value required at end of module
