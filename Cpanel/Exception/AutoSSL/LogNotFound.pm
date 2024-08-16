package Cpanel::Exception::AutoSSL::LogNotFound;

# cpanel - Cpanel/Exception/AutoSSL/LogNotFound.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

use Cpanel::Time::ISO ();

#Parameters:
#   start_time
#
sub _default_phrase {
    my ($self) = @_;

    my $epoch = Cpanel::Time::ISO::iso2unix( $self->get('start_time') );

    return Cpanel::LocaleString->new(
        'An [asis,AutoSSL] log with a start time of [datetime,_1,datetime_format_medium] [asis,UTC] ([_2]) does not exist on the system.',
        $epoch,
        $self->get('start_time'),
    );
}

1;
