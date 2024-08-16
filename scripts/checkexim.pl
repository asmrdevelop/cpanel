#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - scripts/checkexim.pl                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
package scripts::checkexim;

use strict;
use Cpanel::FileUtils::TouchFile ();
use Cpanel::SafetyBits::Chown    ();
use Cpanel::Lchown               ();

__PACKAGE__->main() unless caller;

sub main {
    checkeximlogs();
    checkeximperms();
}

sub checkeximlogs {
    require Cpanel::PwCache;
    my $mailnull_uid = ( Cpanel::PwCache::getpwnam('mailnull') )[2];

    my $mail_gid = ( getgrnam('mail') )[2];
    if ( opendir( my $exim_dir_fh, '/var/log' ) ) {
        my %log_files = map { $_ => undef } grep { /^exim_/ } readdir($exim_dir_fh);
        $log_files{'exim_mainlog'}   = undef;
        $log_files{'exim_paniclog'}  = undef;
        $log_files{'exim_rejectlog'} = undef;
        foreach my $log_file ( keys %log_files ) {
            my ( $mode, $uid, $gid ) = ( stat( '/var/log/' . $log_file ) )[ 2, 4, 5 ];
            if ( !$mode ) { Cpanel::FileUtils::TouchFile::touchfile( '/var/log/' . $log_file ) }
            Cpanel::Lchown::lchown( $mailnull_uid, $mail_gid, '/var/log/' . $log_file ) if ( $uid != $mailnull_uid || $gid != $mail_gid );
            chmod( 0640, '/var/log/' . $log_file )                                      if ( $mode & 00777 != 0640 );
        }
    }
}

sub checkeximperms {
    my $no_chown_spool = shift;

    require Cpanel::PwCache;
    if ( Cpanel::PwCache::getpwnam("mailnull") ) {
        my $mailnull_uid = ( Cpanel::PwCache::getpwnam('mailnull') )[2];
        my $mail_gid     = ( getgrnam('mail') )[2];

        checkeximlogs();

        # Only chown what really needs it: directories under /var/spool/exim.
        # Chowning everything takes too long on systems with large queues.
        unless ($no_chown_spool) {
            safe_chown_maxdepth( '/var/spool/exim', $mailnull_uid, $mail_gid, 2 );

            # scripts/updatemailscanner needs this. If it's not installed, this will just return.
            safe_chown_maxdepth( '/var/spool/exim_incoming',       $mailnull_uid, $mail_gid, 1 );
            safe_chown_maxdepth( '/var/spool/exim_incoming/db',    $mailnull_uid, $mail_gid, 1 );
            safe_chown_maxdepth( '/var/spool/exim_incoming/input', $mailnull_uid, $mail_gid, 1 );
        }

        chown $mailnull_uid, $mail_gid, '/etc/exim.crt', '/etc/exim.key';
    }
}

sub safe_chown_maxdepth {
    my ( $path, $uid, $gid, $depth ) = @_;
    return if $depth == 0;
    return unless -e $path;

    my @files_to_chown = ($path);
    my @dirs_to_search;

    opendir( my $dh, $path ) or return 0;
    foreach ( grep { /^[^.]/ } readdir($dh) ) {
        if ( -d "$path/$_" ) { push @dirs_to_search, "$path/$_" }
        push @files_to_chown, "$path/$_";
    }

    Cpanel::SafetyBits::Chown::safe_chown( $uid, $gid, @files_to_chown );

    foreach (@dirs_to_search) {
        safe_chown_maxdepth( $_, $uid, $gid, $depth - 1 );
    }
}

1;
