package Cpanel::Config::Session;

# cpanel - Cpanel/Config/Session.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# use strict;

our $SESSION_DIR              = '/var/cpanel/sessions';
our $SESSION_EXPIRE_TIME      = ( 60 * 60 * 24 );         # 24 hrs  - Mtime limit for session file removal (see case 31949)
our $PREAUTH_SESSION_DURATION = ( 5 * 60 );               # 5 min  - Mtime limit for unauthenticted session file removal
our $VERSION                  = 1.0;

# List of session dirs. Also used in unit tests to validate session cleanup.

sub session_dirs {
    return (
        $SESSION_DIR . '/raw',
        $SESSION_DIR . '/cache',
        $SESSION_DIR . '/preauth'
    );
}

1;
