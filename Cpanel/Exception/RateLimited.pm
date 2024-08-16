package Cpanel::Exception::RateLimited;

# cpanel - Cpanel/Exception/RateLimited.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::RateLimited

=head1 SYNOPSIS

    die Cpanel::Exception::create_raw('RateLimited');  ## no extract maketext

=head1 DESCRIPTION

This class indicates a rate-limiting error to give to a caller.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Exception );

1;
