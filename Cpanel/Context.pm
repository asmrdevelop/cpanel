package Cpanel::Context;

# cpanel - Cpanel/Context.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();

#
# We used to use Cpanel::Caller here, however the overhead of the
# additional subroutine calls was causing us to not use Cpanel::Context::must_be_list()
# where it would be beneficial to Cpanel::Caller was changed out to use
# perl's underly caller() function so we can use this module in places
# that are performance sensitive.
#
sub must_be_list {
    return 1 if ( caller(1) )[5];    # 5 = wantarray
                                     #
                                     # Most of the time we will just return right away
                                     # so we check that first and avoid proceeding
                                     # any fruther in this sub
                                     #
    my $msg = ( caller(1) )[3];      # 3 = subroutine
    $msg .= $_[0] if defined $_[0];
    return _die_context( 'list', $msg );
}

sub must_not_be_scalar {
    my ($message) = @_;

    my $wa = ( caller(1) )[5];       # 5 = wantarray

    if ( !$wa && defined $wa ) {
        _die_context( 'list or void', $message );
    }

    return 1;
}

sub must_not_be_void {
    return if defined( ( caller 1 )[5] );

    return _die_context('scalar or list');
}

sub _die_context {
    my ( $context, $message ) = @_;

    local $Carp::CarpInternal{__PACKAGE__} if $INC{'Carp.pm'};

    my $to_throw = length $message ? "Must be $context context ($message)!" : "Must be $context context!";

    #Even though this exception is for internal consumption,
    #give it a type so that higher layers (tests, etc.) know what failed.
    die Cpanel::Exception::create_raw( 'ContextError', $to_throw );
}

1;
