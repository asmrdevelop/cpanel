package Cpanel::SSL::DCV::DNS::Constants;

# cpanel - Cpanel/SSL/DCV/DNS/Constants.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DCV::DNS::Constants

=head1 SYNOPSIS

See below.

=head1 CONSTANTS

=head2 TEST_RECORD_NAME

The name of the record that will be created.

=head2 TEST_RECORD_TYPE

The type of the record that will be created.

=cut

use constant {
    TEST_RECORD_NAME => '_cpanel-dcv-test-record',
    TEST_RECORD_TYPE => 'TXT',
};

1;
