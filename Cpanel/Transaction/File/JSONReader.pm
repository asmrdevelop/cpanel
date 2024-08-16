package Cpanel::Transaction::File::JSONReader;

# cpanel - Cpanel/Transaction/File/JSONReader.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: If you need to edit, use the "JSON" class.
#----------------------------------------------------------------------

use strict;

use base qw(
  Cpanel::Transaction::File::Read::JSON
  Cpanel::Transaction::File::BaseReader
);

1;
