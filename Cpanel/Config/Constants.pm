package Cpanel::Config::Constants;

# cpanel - Cpanel/Config/Constants.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# System Default constant for cPanel Theme. This gets applied if for any reason cPanel default theme
# fails to be retrieved from wwwacctconf file or if it is not present in that file (i.e. if
# it is not set through Basic cPanel&WHM page.)
# This is a READONLY value and SHOULD NOT be over-written anywhere else.
our $DEFAULT_CPANEL_THEME = 'jupiter';

# System Default constant for cPanel Theme if falling back from legacy mailonly scheme.
# This gets applied if for any reason the server set cPanel Theme does not have a *mail equivelent
# This is a READONLY value and SHOULD NOT be over-written anywhere else.
our $DEFAULT_CPANEL_MAILONLY_THEME = 'jupiter';

# System Default constant for Webmail Theme. This gets applied if for any reason Webmail default theme
# fails to be retrieved from wwwacctconf file or if it is not present in that file (i.e. if
# it is not set through Basic cPanel&WHM page.)
# This is a READONLY value and SHOULD NOT be over-written anywhere else.
our $DEFAULT_WEBMAIL_THEME = 'jupiter';

# System Default constant for Webmail Theme if falling back from legacy mailonly scheme.
# This gets applied if for any reason the server set Webmail Theme does not have a *mail equivelent
# This is a READONLY value and SHOULD NOT be over-written anywhere else.
our $DEFAULT_WEBMAIL_MAILONLY_THEME = 'jupiter';

# List of services which can be set as dormant
our @DORMANT_SERVICES_LIST = qw(cpdavd cphulkd cpsrvd dnsadmin spamd);

# Up to two days to stream an account
our $MAX_HOMEDIR_STREAM_TIME = ( 86400 * 2 );

1;
