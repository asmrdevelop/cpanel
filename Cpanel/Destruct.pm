package Cpanel::Destruct;

# cpanel - Cpanel/Destruct.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
##
##
##  THIS MODULE IS ONLY CALLED FROM DESTROY HANDLERS.  IT SHOULD NEVER HAVE ANY
##  EXTERNAL DEPENDENCIES OR CREATE ANY OBJECTS AS ITS PRIMARY PURPOSE IS TO
##  AVOID DESTROY HANDLERS THAT WILL CAUSE perlcc BINARIES TO CRASH DURING
##  GLOBAL DESTRUCTION AND WARN WHEN THE OBJECTS WERE NOT TORN DOWN BEFOREHAND.
##
##
my $in_global_destruction = 0;
my ( $package, $filename, $line, $subroutine );    # preallocate

#“Dangerous” global destruction means global destruction in compiled code.
sub in_dangerous_global_destruction {

    #The problem is that we don’t know of a reliable way to detect whether we
    #are running in compiled code. The best substitute, for now, is to check
    #%INC to see if we have testing modules loaded.
    if ( !$INC{'Test2/API.pm'} ) {

        #All of our binaries should now have Cpanel::BinCheck loaded.
        return 1 if in_global_destruction() && $INC{'Cpanel/BinCheck.pm'};
    }

    return 0;
}

sub in_global_destruction {
    return $in_global_destruction if $in_global_destruction;

    if ( defined( ${^GLOBAL_PHASE} ) ) {
        if ( ${^GLOBAL_PHASE} eq 'DESTRUCT' ) {
            $in_global_destruction = 1;
        }
    }

    # There is no good way to detect this prior to Perl 5.14 since
    # ${^GLOBAL_PHASE} is not supported.
    else {
        local $SIG{'__WARN__'} = \&_detect_global_destruction_pre_514_WARN_handler;
        warn;
    }

    return $in_global_destruction;
}

sub _detect_global_destruction_pre_514_WARN_handler {
    if ( length $_[0] > 26 && rindex( $_[0], 'during global destruction.' ) == ( length( $_[0] ) - 26 ) ) {
        $in_global_destruction = 1;
    }

    return;
}

1;
