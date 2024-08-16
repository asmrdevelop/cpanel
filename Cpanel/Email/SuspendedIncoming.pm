package Cpanel::Email::SuspendedIncoming;

# cpanel - Cpanel/Email/SuspendedIncoming.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This module only concerns the stored on/off FileProtect state.
# To enable or disable fileprotect, use scripts/enablefileprotect
# and scripts/disablefileprotect.
#
# See base class for full documentation.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Config::TouchFileBase );

use Cpanel ();

my $FILENAME = '.suspended_incoming';

sub _TOUCH_FILE {
    my ( $self, $account ) = @_;

    die "Need \$Cpanel::homedir!" if !defined $Cpanel::homedir;

    my $base = "$Cpanel::homedir/etc/";
    if ( $account && ( $account ne $Cpanel::user ) ) {

        my ( $login, $domain, $extra ) = split m<@>, $account;

        if ( ( $account =~ tr</><> ) || !length($domain) || length($extra) ) {
            die "Invalid email account: “$account”";
        }

        $base .= ".$account";
    }

    return $base . $FILENAME;
}

1;
