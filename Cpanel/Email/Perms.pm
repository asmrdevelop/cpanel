package Cpanel::Email::Perms;

# cpanel - Cpanel/Email/Perms.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# CONSTANTS
our ( $NEEDS_GID_MAIL, $NEEDS_GID_MAIL_IF_NOT_EXTERNAL_AUTH, $NEEDS_GID_USER, $CREATE_NO, $CREATE_OK ) = ( 1, 2, 3, 0, 1 );

#0751 to access from SMTP
our $MAILDIR_PERMS = 0751;

our $ETC_PERMS = 0750;

# FIELD CONSTANTS
our ( $FIELD_PERMS, $FIELD_GID, $FIELD_CREATE ) = ( 0, 1, 2 );

# SETTINGS
our ($VERBOSE);

1;
