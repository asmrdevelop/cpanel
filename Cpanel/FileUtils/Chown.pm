package Cpanel::FileUtils::Chown;

# cpanel - Cpanel/FileUtils/Chown.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::FileUtils::Open ();

sub check_and_fix_owner_and_permissions_for {
    my (%opts) = @_;

    my $count_changed = 0;

    # path must be provided
    return unless defined $opts{path};

    die q[Unsupported 'perm' option, please use 'octal_perms' instead.] if exists $opts{perm};

    my $set_file_octal_perms;
    if ( defined $opts{octal_perms} ) {
        $set_file_octal_perms = $opts{octal_perms};
    }

    my $file_exist = -e $opts{path};
    if ( $opts{create} && !$file_exist ) {

        {
            my $need_perms = $set_file_octal_perms // 0640;
            Cpanel::FileUtils::Open::sysopen_with_real_perms( my $fh, $opts{path}, 'O_WRONLY|O_CREAT|O_EXCL', $need_perms );
        }

        $file_exist = -e $opts{path};
        ++$count_changed if $file_exist;
    }
    return unless $file_exist;

    my ( $mode, $uid, $gid ) = ( stat( $opts{path} ) )[ 2, 4, 5 ];

    # fixer owner and group
    # one of these two options need to be defined set the group
    if (   defined $opts{user}
        or defined $opts{group}
        or defined $opts{uid}
        or defined $opts{gid} ) {
        my ( $expected_uid, $expected_gid );

        # used in scalar context
        $expected_uid = getpwnam( $opts{user} )  if defined $opts{user};
        $expected_gid = getgrnam( $opts{group} ) if defined $opts{group};

        # we should use //= //
        unless ( defined $expected_uid ) {
            for my $c ( $opts{uid}, $uid ) {
                $expected_uid = $c;
                last if defined $c;
            }
        }
        unless ( defined $expected_gid ) {
            for my $c ( $opts{gid}, $gid ) {
                $expected_gid = $c;
                last if defined $c;
            }
        }
        if (   defined $expected_uid
            && defined $expected_gid
            && ( $expected_uid != $uid || $expected_gid != $gid ) ) {
            $count_changed += chown $expected_uid, $expected_gid, $opts{path};
        }
    }

    my $actual_perm = $mode & 07777;
    if ( defined $set_file_octal_perms && $set_file_octal_perms != $actual_perm ) {
        $count_changed += chmod( $set_file_octal_perms, $opts{path} );
    }

    return $count_changed;
}

1;
