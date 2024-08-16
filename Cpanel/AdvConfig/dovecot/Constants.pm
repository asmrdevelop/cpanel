package Cpanel::AdvConfig::dovecot::Constants;

# cpanel - Cpanel/AdvConfig/dovecot/Constants.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant {
    MINIMUM_LOGIN_PROCESS_SIZE   => 128,
    MINIMUM_MAIL_PROCESS_SIZE    => 512,
    RECOMMENDED_CONFIG_VSZ_LIMIT => 2048,
    DEFAULT_PLUGIN_ACL           => 'vfile:cache_secs=86400',    # we never expect this to change since we only write it once in Cpanel::Email::Archive
    DEFAULT_AUTH_CACHE_SIZE      => '1M',
};

1;
