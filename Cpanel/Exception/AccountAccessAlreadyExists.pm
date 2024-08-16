package Cpanel::Exception::AccountAccessAlreadyExists;

# cpanel - Cpanel/Exception/AccountAccessAlreadyExists.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::Exception::AccountAccessAlreadyExists

=head1 SYNOPSIS

    Cpanel::Exception::create( 'AccountAccessAlreadyExists', $message );

=cut

use parent qw( Cpanel::Exception::EntryAlreadyExists );

1;
