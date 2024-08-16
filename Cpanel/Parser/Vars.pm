package Cpanel::Parser::Vars;

# cpanel - Cpanel/Parser/Vars.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $current_tag            = '';
our $can_leave_cpanelaction = 1;
our $buffer                 = '';

our $loaded_api   = 0;
our $trial_mode   = 0;
our $sent_headers = 0;
our $live_socket_file;

our $incpanelaction = 0;
our $altmode        = 0;
our $jsonmode       = 0;
our $javascript     = 0;
our $title          = 0;
our $input          = 0;
our $style          = 0;
our $embtag         = 0;
our $textarea       = 0;

our $file           = '[stdin]';
our $firstfile      = '[stdin]';
our $trap_defaultfh = undef;       # Known to be boolean.

our %BACKCOMPAT;

our $cptag;
our $sent_content_type;

1;
