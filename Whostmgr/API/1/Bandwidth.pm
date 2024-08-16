package Whostmgr::API::1::Bandwidth;

# cpanel - Whostmgr/API/1/Bandwidth.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Whostmgr::Authz     ();
use Whostmgr::Bandwidth ();

use constant ARGUMENT_NEEDS_PARENT => {
    limitbw => 'user',
};

use constant NEEDS_ROLE => {
    showbw  => undef,
    limitbw => undef,
};

sub showbw {
    my ( $args, $metadata ) = @_;

    local $SIG{'__WARN__'} = sub ($msg) {
        $metadata->add_warning($msg);
    };

    if ( defined $args->{'month'} ) {
        my $month = $args->{'month'} + 0;

        if ( $month < 1 || $month > 12 ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = 'Invalid month provided';
            return;
        }
    }
    if ( defined $args->{'year'} ) {
        my $year = $args->{'year'} + 0;

        if ( $year < 1970 || $year > 2200 ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = 'Invalid year provided';
            return;
        }
    }

    my $rsd_ref = Whostmgr::Bandwidth::_showbw(%$args);
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return $rsd_ref->[0] if 'ARRAY' eq ref $rsd_ref;
    return;
}

#params:
#   - user
#   - bwlimit
#
sub limitbw {
    my ( $args, $metadata ) = @_;

    Whostmgr::Authz::verify_account_access( $args->{'user'} );

    my ( $status, $statusmsg, $bwlimit ) = Whostmgr::Bandwidth::setbwlimit( 'user' => $args->{'user'}, 'bwlimit' => $args->{'bwlimit'} );
    $metadata->{'result'} = $status ? 1 : 0;
    $metadata->{'reason'} = $statusmsg;
    return { 'bwlimits' => [$bwlimit] } if $status;
    return;
}

1;
