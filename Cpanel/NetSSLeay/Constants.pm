package Cpanel::NetSSLeay::Constants;

# cpanel - Cpanel/NetSSLeay/Constants.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#These correspond to the “reason” component of an OpenSSL error code.
#cf. OpenSSL include/openssl/ocsp.h
use constant OCSP_R_STATUS_EXPIRED       => 125;
use constant OCSP_R_STATUS_NOT_YET_VALID => 126;
use constant OCSP_R_STATUS_TOO_OLD       => 127;

1;
