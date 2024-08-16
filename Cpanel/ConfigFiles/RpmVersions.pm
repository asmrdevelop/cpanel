package Cpanel::ConfigFiles::RpmVersions;

# cpanel - Cpanel/ConfigFiles/RpmVersions.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $RPM_VERSIONS_FILE         = q{/usr/local/cpanel/etc/rpm.versions};
our $RPM_VERSIONS_SANDBOX_FILE = q{/usr/local/cpanel/build-tools/rpm.versions.sandbox/sandbox.versions};

1;
