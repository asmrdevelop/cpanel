package Cpanel::Email::Accounts::Paths;

# cpanel - Cpanel/Email/Accounts/Paths.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Email::Accounts::Paths - Paths and files for email account data.

=cut

our $EMAIL_SUSPENSIONS_BASE_PATH = '/var/cpanel/email_send_limits/users';
our $EMAIL_SUSPENSIONS_FILE_NAME = 'suspensions.json';
our $EMAIL_HOLDS_BASE_PATH       = '/var/cpanel/email_holds/track';
our $EXIM_QUEUE_INPUT_DIR        = '/var/spool/exim/input';

1;
