package Cpanel::Exception::ProcessEuidMismatch;

# cpanel - Cpanel/Exception/ProcessEuidMismatch.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();
use Cpanel::PwUtils      ();

#Parameters:
#   pid
#   expected
#   found
sub _default_phrase {
    my ($self) = @_;

    my ( $expected_uid,  $found_uid )  = map { Cpanel::PwUtils::normalize_to_uid($_) } @{ $self->{'_metadata'} }{qw(expected found)};
    my ( $expected_name, $found_name ) = map { scalar( ( getpwuid $_ )[0] ) } ( $expected_uid, $found_uid );

    return Cpanel::LocaleString->new(
        'The process with ID “[_1]” should have the effective user “[_2]” (UID [_3]), but its effective user is actually “[_4]” ([_5]).',
        $self->{'_metadata'}{'pid'},
        $expected_name,
        $expected_uid,
        $found_name,
        $found_uid,
    );
}

1;
