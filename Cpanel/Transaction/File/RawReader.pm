package Cpanel::Transaction::File::RawReader;

# cpanel - Cpanel/Transaction/File/RawReader.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: If you need to edit, use the "Raw" class.
#----------------------------------------------------------------------

use strict;

use base qw(
  Cpanel::Transaction::File::Read::Raw
  Cpanel::Transaction::File::BaseReader
);

1;
