package Cpanel::Transaction::File::LoadConfigReader;

# cpanel - Cpanel/Transaction/File/LoadConfigReader.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: If you need to edit, use the "LoadConfig" class.
#----------------------------------------------------------------------

use strict;

use parent qw(
  Cpanel::Transaction::File::Read::LoadConfig
  Cpanel::Transaction::File::BaseReader
);

1;
