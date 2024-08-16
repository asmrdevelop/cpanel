package Cpanel::Pack::Template;

# cpanel - Cpanel/Pack/Template.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Pack::Template - Human readable names for pack

=head1 SYNOPSIS

    use Cpanel::Pack::Template;

	my $packed_ints = pack( Cpanel::Pack::Template::PACK_TEMPLATE_INT x scalar @_, @_ );

=cut

##
## do not convert them to GVs or this could be an issue with cppack and breaks /etc/exim.pl.local
##
#-----------------------------------------------------------------

use constant PACK_TEMPLATE_INT           => 'i';
use constant PACK_TEMPLATE_UNSIGNED_INT  => 'i!';
use constant PACK_TEMPLATE_UNSIGNED_LONG => 'L!';
use constant PACK_TEMPLATE_U32           => 'L';
use constant U32_BYTES_LENGTH            => 4;
use constant PACK_TEMPLATE_U16           => 'S';
use constant U16_BYTES_LENGTH            => 2;
use constant PACK_TEMPLATE_U8            => 'C';
use constant U8_BYTES_LENGTH             => 1;
use constant PACK_TEMPLATE_BE16          => 'n';
use constant PACK_TEMPLATE_BE32          => 'N';

1;
