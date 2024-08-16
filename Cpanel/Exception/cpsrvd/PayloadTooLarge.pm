package Cpanel::Exception::cpsrvd::PayloadTooLarge;

# cpanel - Cpanel/Exception/cpsrvd/PayloadTooLarge.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::cpsrvd::PayloadTooLarge

=head1 SYNOPSIS

    die Cpanel::Exception::create('cpsrvd::PayloadTooLarge');

=head1 DESCRIPTION

This exception tells cpsrvd to send an HTTP “Payload Too Large” error
as the request response.

=cut

use parent qw( Cpanel::Exception::cpsrvd );

use constant HTTP_STATUS_CODE => 413;

1;
