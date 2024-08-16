package Cpanel::MultiUserDirStore::VirtualUser::TimeIndexedData;

# cpanel - Cpanel/MultiUserDirStore/VirtualUser/TimeIndexedData.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception ();

use parent qw(
  Cpanel::MultiUserDirStore::VirtualUser
  Cpanel::MultiUserDirStore::TimeIndexedData
);

sub new {
    my ( $class, %OPTS ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is missing.',    ['keep_time'] ) if !$OPTS{'keep_time'};
    die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” must be a whole number.', ['keep_time'] ) if $OPTS{'keep_time'} !~ m{^[1-9][0-9]*$};

    my $obj = $class->SUPER::new(%OPTS);

    $obj->{'keep_time'} = $OPTS{'keep_time'};

    return $obj;
}

1;
