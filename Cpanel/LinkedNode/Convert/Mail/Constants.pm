package Cpanel::LinkedNode::Convert::Mail::Constants;

# cpanel - Cpanel/LinkedNode/Convert/Mail/Constants.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::Mail::Constants

=head1 DESCRIPTION

This module contains constants for distributed-mail conversions.

=head1 CONSTANTS

=head2 C<HOMEDIR_PATHS>

Returns a list of mail-related paths from the home directory.

=cut

use constant HOMEDIR_PATHS => (
    'etc',
    'mail',
    '.spamassassin',
    '.spamassassinenable',
    '.spamassassindisable',
    '.spamassassinboxenable',
    '.spamassassinboxdisable',
);

1;
