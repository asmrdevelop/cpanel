package Cpanel::Email::Constants;

# cpanel - Cpanel/Email/Constants.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Email::Constants

=head1 DESCRIPTION

This module implements various email-related constants.

=head1 CONSTANTS

=head2 VDIR_PERMS

valiases, vdomainaliases, and vfilters are "vdir"s.
They’re owned by root:mail.
Users need to read their own files, and we configure Exim
to use dsearch, which means we need Exim to read the directories.

=cut

sub VDIR_PERMS { return 0751; }

=head2 VFILE_PERMS

files in valiases, vdomainaliases, and vfilters are "vfile"s.
They’re owned by $username:mail.

=cut

sub VFILE_PERMS { return 0640; }

=head2 SYNC_TIMEOUT

The number of seconds before a user’s mailbox-sync operation should
time out. Given that some mailboxes contain huge amounts of mail this
should be quite generous.

=cut

use constant SYNC_TIMEOUT => 2 * 86400;

1;
