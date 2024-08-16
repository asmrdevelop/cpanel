package Cpanel::JailSafe::Install;

# cpanel - Cpanel/JailSafe/Install.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::JailSafe ();

sub do_symlink_jail_safe_for {
    my ( $name, $setuid ) = @_;

    my $jail_safe = '/usr/local/cpanel/bin/jail_safe_' . $name;
    my $bin_path  = $Cpanel::JailSafe::SYSTEM_BIN_DIR . '/' . $name;

    #
    # on CentOS7 /bin is a symlink to /usr/bin
    #
    if ( -l $Cpanel::JailSafe::SYSTEM_BIN_DIR ) {    # /bin (just a variable for testing)
        my $system_bin = Cpanel::JailSafe::get_system_binary($name);

        # If it was previously moved away, put it back in place
        # as we will put the link in /usr/local/bin instead
        #
        if ( $system_bin && $system_bin =~ m{\Q$Cpanel::JailSafe::RELINK_POSTFIX\E} ) {

            unlink($bin_path) if -l $bin_path;

            {
                local $!;
                rename $system_bin, $bin_path or warn "Failed to rename “$system_bin” to “$bin_path”: $!";
            }

            if ($setuid) {
                chmod( 04755, $bin_path );
            }
        }

        #
        # On Cent7 we put the link in /usr/local/bin
        # since it comes before /usr/bin and /bin in the default
        # path
        # which looks like
        # /usr/local/jdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/usr/local/bin:/usr/X11R6/bin:/root/bin
        #
        #
        $bin_path = "$Cpanel::JailSafe::SYSTEM_USR_LOCAL_BIN_DIR/$name";
    }

    if ( -e $bin_path && -l $bin_path && readlink($bin_path) eq $jail_safe ) {
        return;
    }

    unlink $bin_path if -l $bin_path;

    if ( !symlink( $jail_safe, $bin_path ) ) {
        warn "Failed to symlink $jail_safe to $bin_path: $!";
    }

    return;
}

1;
