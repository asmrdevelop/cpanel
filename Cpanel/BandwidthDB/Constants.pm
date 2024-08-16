package Cpanel::BandwidthDB::Constants;

# cpanel - Cpanel/BandwidthDB/Constants.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::WildcardDomain::Constants ();

our $MIN_ACCEPTED_TIMESTAMP = 820454400;    #1 Jan 1996 - “cPanel day 1”

our $MAX_ACCEPTED_TIMESTAMP = ( 1 << 32 ) - 1;

our $UNKNOWN_DOMAIN_NAME = 'UNKNOWN';

our $DIRECTORY = '/var/cpanel/bandwidth';

our $ROOT_CACHE_PATH = '/var/cpanel/bandwidth_cache.sqlite';

our $DB_FILE_PERMS = 0640;

our $ROOT_CACHE_FILE_PERMS = 0600;

our @REPORT_TABLE_COLUMNS = qw(
  domain_id
  protocol
  unixtime
  bytes
);

our $SCHEMA_VERSION = 3;

our @WILDCARD_PREFIXES = (
    $Cpanel::WildcardDomain::Constants::PREFIX,
    '__wildcard__',    #historical, specific to bandwidth
    '*',
);

# This is DISPLAY ORDER, http must always be first
# for backwards compat
our @PROTOCOLS = qw(
  http
  ftp
  imap
  pop3
  smtp
);

our @INTERVALS = qw(
  5min
  daily
  hourly
);

1;
