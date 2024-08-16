package Cpanel::Session::Constants;

# cpanel - Cpanel/Session/Constants.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $CPSES_DIR         = '/var/cpanel/cpses';
our $CPSES_KEYS_DIR    = "$CPSES_DIR/keys";
our $CPSES_MAILMAN_DIR = "$CPSES_DIR/mailman";
our $CPSES_LOOKUP_DIR  = "$CPSES_DIR/lookup";

# If you change this value, you must change Cpanel::Validate::Username::Core.
our $TEMP_USER_PREFIX = 'cpses_';

# We use a string unlikely to be in the password
# A non breaking space was tried at first
our $TEMP_SEPARATOR = '[::cpses::]';

1;
