package Whostmgr::DNS::Constants;

# cpanel - Whostmgr/DNS/Constants.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#"0" is also allowed as a legacy setting
#
our @MXCHECK_OPTIONS = qw(
  auto
  local
  remote
  secondary
);

1;
