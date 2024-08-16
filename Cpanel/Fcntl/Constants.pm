package Cpanel::Fcntl::Constants;

# cpanel - Cpanel/Fcntl/Constants.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# This module must not have any external deps
# as it is being used in exim

BEGIN {
    our $O_RDONLY  = 0;
    our $O_WRONLY  = 1;
    our $O_RDWR    = 2;
    our $O_ACCMODE = 3;

    our $F_GETFD = 1;
    our $F_SETFD = 2;
    our $F_GETFL = 3;
    our $F_SETFL = 4;

    our $SEEK_SET    = 0;
    our $SEEK_CUR    = 1;
    our $SEEK_END    = 2;
    our $S_IWOTH     = 2;
    our $S_ISUID     = 2048;
    our $S_ISGID     = 1024;
    our $O_CREAT     = 64;
    our $O_EXCL      = 128;
    our $O_TRUNC     = 512;
    our $O_APPEND    = 1024;
    our $O_NONBLOCK  = 2048;
    our $O_DIRECTORY = 65536;
    our $O_NOFOLLOW  = 131072;
    our $O_CLOEXEC   = 524288;

    our $S_IFREG  = 32768;
    our $S_IFDIR  = 16384;
    our $S_IFCHR  = 8192;
    our $S_IFBLK  = 24576;
    our $S_IFIFO  = 4096;
    our $S_IFLNK  = 40960;
    our $S_IFSOCK = 49152;
    our $S_IFMT   = 61440;

    our $LOCK_SH = 1;
    our $LOCK_EX = 2;
    our $LOCK_NB = 4;
    our $LOCK_UN = 8;

    our $FD_CLOEXEC = 1;
}

1;
