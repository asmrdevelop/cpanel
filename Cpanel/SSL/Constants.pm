package Cpanel::SSL::Constants;

# cpanel - Cpanel/SSL/Constants.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Constants

=head1 DESCRIPTION

Selected constants relevant to SSL/TLS.

=cut

#----------------------------------------------------------------------

=head1 CONSTANTS

=head2 C<MAX_CN_LENGTH>

The maximum length of a subject or issuer C<commonName>.

As defined in L<RFC 5280|https://tools.ietf.org/html/rfc5280#page-124>.

=cut

use constant MAX_CN_LENGTH => 64;

1;
