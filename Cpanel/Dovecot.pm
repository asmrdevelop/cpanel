package Cpanel::Dovecot;

# cpanel - Cpanel/Dovecot.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $VERSION = 1.2;

our $CP_DOVECOT_STORAGE          = '/var/cpanel/dovecot';
our $SQLITE_LASTLOGIN_DB_FILE    = $CP_DOVECOT_STORAGE . '/dict.lastlogin.sqlite';    # no longer used, kept only so we know which file to remove
our $PLAINTEXT_CONFIG_CACHE_FILE = '/var/cpanel/dovecot_disable_plaintext_auth';      # TODO: move to Cpanel::Dovecot::Constants

our $LASTLOGIN_DIR = "$CP_DOVECOT_STORAGE/last-login";

#cf. Dovecot source code, src/doveadm/doveadm.h
# Dovecot just uses Unix Sysexit codes
# We originally used Unix::Sysexits, however it was
# removed to reduce memory usage.
our $DOVEADM_EX_NOTFOUND;    #EX_NOHOST
our $DOVEADM_EX_NOUSER;      #EX_NOUSER
our $DOVEADM_EX_TEMPFAIL;    #EX_TEMPFAIL
our $DOVEADM_EX_OKBUTDOAGAIN;

BEGIN {
    $DOVEADM_EX_NOTFOUND     = 68;    #EX_NOHOST
    $DOVEADM_EX_NOUSER       = 67;    #EX_NOUSER
    $DOVEADM_EX_TEMPFAIL     = 75;    #EX_TEMPFAIL
    $DOVEADM_EX_OKBUTDOAGAIN = 2;     # No pretty label. See https://doc.dovecot.org/admin_manual/error_codes/
}

1;
