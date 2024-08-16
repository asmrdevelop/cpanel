package Cpanel::Path::Basename;

# cpanel - Cpanel/Path/Basename.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use File::Basename ();

# This used to be an implemntation of File::Basename when it
# was bloated.  The latest version ony uses 92k
# root      7767  0.0  0.0 127432  3360 pts/5    S+  17:45  0:00 ./3rdparty/bin/perl -MIO::File -e print `ps -u -p $$`
# root      7779  3.0  0.0 127564  3452 pts/5    S+  17:45  0:00 ./3rdparty/bin/perl -MIO::File -MFile::Basename -e print `ps -u -p $$`
#
# As such this module is now a stub that points to File::Basename

*fileparse = \&File::Basename::fileparse;
*basename  = \&File::Basename::basename;
*dirname   = \&File::Basename::dirname;

1;
