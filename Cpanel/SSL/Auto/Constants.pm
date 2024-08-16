package Cpanel::SSL::Auto::Constants;

# cpanel - Cpanel/SSL/Auto/Constants.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Constants - values for multiple AutoSSL modules

=head1 SYNOPSIS

    $ttl = $Cpanel::SSL::Auto::Constants::LOG_TTL

=head1 DESCRIPTION

Nothing much to this one!

=cut

our $LOG_TTL = 86400 * 30;    #30 days

1;
