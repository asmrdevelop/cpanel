package Cpanel::ForcePassword::Unforce;

# cpanel - Cpanel/ForcePassword/Unforce.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::PwCache  ();
use Cpanel::Logger   ();
use Cpanel::Fcntl    ();
use Cpanel::SafeFile ();

sub unforce_password_change {
    my ( $sysuser, $user, $homedir ) = @_;
    return unless -d $homedir;
    my $file = $homedir . '/.cpanel/passwordforce';
    return unless -f $file;

    if ( $< == 0 ) {
        my ( $gid, $uid ) = ( Cpanel::PwCache::getpwnam($sysuser) )[ 3, 2 ];
        if ( !defined $uid ) {
            my $logger = Cpanel::Logger->new();
            $logger->warn("User '$sysuser' not found. Do not change password force status.\n");
            return;
        }

        # Temporarily change the UID/GID just long enough to update the file.
        # Using Cpanel::AccessIds would require a fork for this call. That gets
        # expensive in the WHM interface.
        local ( $), $> ) = ( "$gid $gid", $uid );
        my $setuid_err = $!;
        if ( $> == $uid ) {
            return _real_unforce_password_change( $sysuser, $user, $file );
        }
        my $logger = Cpanel::Logger->new();
        $logger->warn("Unable to change uid to $uid: $setuid_err.\n");
        return 0;
    }

    return _real_unforce_password_change( $sysuser, $user, $file );
}

sub _real_unforce_password_change {
    my ( $sysuser, $user, $file ) = @_;
    my $fh;
    my $lock = Cpanel::SafeFile::safesysopen( $fh, $file, Cpanel::Fcntl::or_flags(qw( O_RDWR O_CREAT )) );
    unless ( defined $lock ) {
        my $logger = Cpanel::Logger->new();
        $logger->warn("Unable to lock/open '$file': $!\n");
        return;
    }
    my @users    = <$fh>;
    my $oldcount = @users;

    # Put the line ending on the username for comparison. That avoids changing
    # all of the lines and then re-adding the end of line when we write them
    # out again.
    my $match = $user . $/;
    @users = grep { $_ ne $match } @users;
    if (@users) {

        # Only write if we've changed the list.
        if ( $oldcount != @users ) {
            seek( $fh, 0, 0 );
            print $fh @users;
            truncate( $fh, tell($fh) );
        }

        Cpanel::SafeFile::safeclose( $fh, $lock );
    }
    else {

        # no keys, so delete file.
        close($fh);
        unlink($file);
        Cpanel::SafeFile::safeunlock($lock);
    }
    return 1;
}

1;
