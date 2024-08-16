package Cpanel::Exception::Caller;

# cpanel - Cpanel/Exception/Caller.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This includes the calling function as part of the message.
# If this is undesirable, look at @CALLERS_TO_EXCLUDE_FROM_MESSAGE.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::Caller ();

#If the caller is one of these functions, exclude the caller from the messages.
my @CALLERS_TO_EXCLUDE_FROM_MESSAGE = (
    q<Whostmgr::API::1::Utils::get[a-z_]+argument>,
    q<Cpanel::JSON::>
);

sub _get_caller_name {
    my $i = 0;
    my $caller_name;
    while ( my $sub = Cpanel::Caller::subroutine( $i++ ) ) {
        last if ( $sub =~ m{::BEGIN$} );
        next if $sub eq 'Cpanel::Exception::__ANON__';    # do not advertise anonymous sub from Cpanel::Exception
        $caller_name = $sub;
        next if index( $caller_name, '::_' ) > -1 || grep { $caller_name =~ m<$_> } @CALLERS_TO_EXCLUDE_FROM_MESSAGE;
        last if ( $caller_name !~ m{^Cpanel::Exception} );
    }
    return $caller_name;
}

1;
