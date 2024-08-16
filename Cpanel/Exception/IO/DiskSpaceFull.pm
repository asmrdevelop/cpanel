package Cpanel::Exception::IO::DiskSpaceFull;

# cpanel - Cpanel/Exception/IO/DiskSpaceFull.pm    Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

# metadata parameters:
#
sub _default_phrase ( $self, @ ) {
    return Cpanel::LocaleString->new('You have reached your quota limit. Please increase the quota or clean up disk space.');
}

1;
