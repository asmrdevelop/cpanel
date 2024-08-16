package Cpanel::JailSafe;

# cpanel - Cpanel/JailSafe.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# only use for unit tests
our $SYSTEM_BIN_DIR           = q{/bin};              # Path for Cent5 and Cent6
our $SYSTEM_USR_LOCAL_BIN_DIR = q{/usr/local/bin};    # Alternate path for Cent7
our $ROOT_BIN                 = q{/usr/bin};
our $RELINK_POSTFIX           = '.relink.';

# CentOS 7 can use a symlink for /bin to /usr/bin
#   in that case we would like to use the backup performed by CpanelPost
sub get_system_binary {
    my $bin = shift;
    return unless defined $bin;
    my $usr_bin = $ROOT_BIN . '/' . $bin;

    # just pass when it s not available
    return unless -x $usr_bin;

    # avoid an infinite loop... ( only handle a depth=1 )
    if ( !-l $usr_bin || readlink($usr_bin) !~ m{/jail_safe_} ) {
        return $usr_bin;
    }

    # let s now search the backup... ( /bin can be a symlink to /usr/bin )
    my ( $exe, $t );
    if ( opendir my $dh, $ROOT_BIN ) {
        while ( my $f = readdir $dh ) {
            if ( $f =~ m{${bin}\Q$RELINK_POSTFIX\E([0-9]+)$} ) {
                if ( !$t || $t < $1 ) {
                    $t   = $1;
                    $exe = $ROOT_BIN . '/' . $f;
                }
            }
        }
    }
    return $exe if $exe && -x $exe;
    return;
}
1;
