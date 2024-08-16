package Cpanel::Exception::Database::ConnectError;

# cpanel - Cpanel/Exception/Database/ConnectError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::Database::ConnectError

=head1 DESCRIPTION

This exception is thrown in response to a connection failure.
The interface is identical to that of L<Cpanel::Exception::Database::Error>.

=cut

use strict;
use warnings;

use Cpanel::LocaleString ();

use parent qw( Cpanel::Exception::Database::Error );

sub _locale_string_with_dbname {
    return Cpanel::LocaleString->new('The system failed to connect to the “[_1]” database “[_2]” because of an error: [_3]');
}

sub _locale_string_without_dbname {
    return Cpanel::LocaleString->new('The system failed to connect to “[_1]” because of an error: [_2]');
}

1;
