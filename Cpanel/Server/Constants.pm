package Cpanel::Server::Constants;

# cpanel - Cpanel/Server/Constants.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $MAX_ALLOWED_CONTENT_LENGTH_NO_UPLOAD = 1024**2;
our $READ_CONTENT_TIMEOUT_NO_UPLOAD       = 60;

our $MAX_ALLOWED_CONTENT_LENGTH_ALLOW_UPLOAD = 1024**4;
our $READ_CONTENT_TIMEOUT_ALLOW_UPLOAD       = 3600 * 4;    # Four hours

our $FETCHHEADERS_DYNAMIC_CONTENT = 0;
our $FETCHHEADERS_STATIC_CONTENT  = 1;
our $FETCHHEADERS_LOGACCESS       = 0;
our $FETCHHEADERS_SKIP_LOGACCESS  = 1;

our $HTTP_STATUS_OK                  = 200;
our $HTTP_STATUS_NOT_MODIFIED        = 304;
our $HTTP_STATUS_SERVICE_UNAVAILABLE = 503;
our $HTTP_STATUS_INTERNAL_ERROR      = 500;
our $HTTP_STATUS_FORBIDDEN           = 403;

1;
