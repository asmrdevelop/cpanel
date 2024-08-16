package Cpanel::MailLoopProtect;

# cpanel - Cpanel/MailLoopProtect.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::PwCache              ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::SafeDir::MK          ();
use Cpanel::Logger               ();
use Cpanel::Fcntl::Constants     ();

#CONSTANTS

my $MAX_KEEP = 256;
my $TTL      = 1800;         # default TTL (individual files may override this)
my $MAX_TTL  = 86400 * 30;
my $logger;

sub create_delivery_event {
    my ( $email_from, $email_to, $max, $ttl ) = @_;
    $email_from =~ s/\///g;
    $email_to   =~ s/\///g;
    $max ||= 10;
    my $now     = _time();
    my $homedir = _homedir();

    if ( !-d $homedir . '/.cpanel/mailloopprotect' ) {
        if ( !Cpanel::SafeDir::MK::safemkdir( $homedir . '/.cpanel/mailloopprotect', '0700' ) ) {
            $logger ||= Cpanel::Logger->new();
            $logger->warn( 'Could not create dir "' . $homedir . '/.cpanel/mailloopprotect' . '"' );
            return ( 1, 1 );
        }
    }
    else {
        my $last_cleanup_time = ( stat( $homedir . '/.cpanel/mailloopprotect/cleanup_check' ) )[9];
        if ( !$last_cleanup_time || $last_cleanup_time + $TTL < $now || $last_cleanup_time > $now ) {
            clean_old_reports($homedir);
            Cpanel::FileUtils::TouchFile::touchfile( $homedir . '/.cpanel/mailloopprotect/cleanup_check' );
        }
    }

    if ( !-d "$homedir/.cpanel/mailloopprotect/$email_from/$email_to" ) {
        my $target_dir = $homedir . '/.cpanel/mailloopprotect';
        foreach my $subdir ( $email_from, $email_to ) {
            $target_dir .= "/$subdir";
            if ( !-e $target_dir && !Cpanel::SafeDir::MK::safemkdir( $target_dir, '0700' ) ) {
                $logger ||= Cpanel::Logger->new();
                $logger->warn( 'Could not create dir "' . $target_dir . '"' );
                return ( 1, 1 );
            }
        }
        _generate_delivery_event_file( $homedir, $email_from, $email_to, $now, $max, $ttl );
        return ( 1, 1 );
    }

    my $generated = _generate_delivery_event_file( $homedir, $email_from, $email_to, $now, $max, $ttl );
    my $count     = _get_responsecount_and_cleanup( $homedir, $email_from, $email_to, $now );
    return ( $generated && $count <= $max ? 1 : 0, $count );
}

sub clean_old_reports {
    my $homedir          = shift || _homedir();
    my $loop_protect_dir = $homedir . '/.cpanel/mailloopprotect';

    return if ( !-d $loop_protect_dir );
    my $now = _time();

    if ( opendir( my $dir_fh, $loop_protect_dir ) ) {
        while ( my $email_from = readdir($dir_fh) ) {
            next if $email_from =~ /^\.+$/;
            if ( opendir( my $fromdir_fh, "$loop_protect_dir/$email_from" ) ) {
                while ( my $email_to = readdir($fromdir_fh) ) {
                    next if $email_to =~ /^\.+$/;
                    _get_responsecount_and_cleanup( $homedir, $email_from, $email_to, $now );
                }
                closedir($fromdir_fh);
            }
            else {
                unlink("$loop_protect_dir/$email_from");    #old style
            }
            rmdir $loop_protect_dir . '/' . $email_from;    # fail ok if not empty (faster than checking for emptiness)
        }
        closedir($dir_fh);
    }
}

sub get_lastresponse_time {
    my ( $homedir, $email_from, $email_to ) = @_;
    if ( opendir( my $dir_fh, "$homedir/.cpanel/mailloopprotect/$email_from/$email_to" ) ) {
        my %all_files = map { $_ => undef } grep { !/^\.+$/ } readdir($dir_fh);
        closedir($dir_fh);
        return 0 if !scalar keys %all_files;
        return ( split( /-/, ( sort { ( split( /-/, $b ) )[0] <=> ( split( /-/, $a ) )[0] } keys %all_files )[0] ) )[0];
    }
    return 0;
}

# Prior to case 51747, mail loop protect files were based only on the sender address.
# This cleans those up, should they still exist.  Eventually, it can probably go away.
sub _legacy_cleanup {
    my ($dir) = @_;
    if ( opendir my $dir_fh, $dir ) {
        unlink map { "$dir/$_" } grep { !/^\.\.?$/ && !-d "$dir/$_" } readdir $dir_fh;
        closedir $dir_fh;
    }
    return;
}

sub _get_responsecount_and_cleanup {
    my ( $homedir, $email_from, $email_to, $now, $mtime, $keep ) = ( $_[0], $_[1], $_[2], $_[3], 0, 0 );
    $now ||= _time();
    if ( opendir( my $dir_fh, "$homedir/.cpanel/mailloopprotect/$email_from/$email_to" ) ) {
        my %all_files = map { $_ => undef } grep { !/^\.+$/ } readdir($dir_fh);
        closedir($dir_fh);
        if (
            my @kill_files = grep {
                $mtime = ( split( /-/, $_ ) )[0];
                my $ttl = _get_ttl_for_file("$homedir/.cpanel/mailloopprotect/$email_from/$email_to/$_");
                ++$keep > $MAX_KEEP || $mtime + $ttl < $now || $mtime > $now
            }
            sort { ( split( /-/, $b ) )[0] <=> ( split( /-/, $a ) )[0] }
            keys %all_files

        ) {
            unlink( map { "$homedir/.cpanel/mailloopprotect/$email_from/$email_to/$_" } @kill_files );
            delete @all_files{@kill_files};
        }
        if ( !scalar keys %all_files ) {
            rmdir "$homedir/.cpanel/mailloopprotect/$email_from/$email_to";
            _legacy_cleanup("$homedir/.cpanel/mailloopprotect/$email_from");
        }
        return scalar keys %all_files;
    }
}

sub _get_ttl_for_file {
    my $file = shift;
    my $ttl;
    my $size = -s $file;
    if ( $size && $size < 256 && sysopen( my $fh, $file, $Cpanel::Fcntl::Constants::O_RDONLY ) ) {
        chomp( $ttl = readline $fh );
        close $fh;
    }

    # It is normal for some files to be empty, in which case the global default is used.
    # The default is applied when reading the files, rather than when writing them.
    $ttl = $TTL     if !$ttl || $ttl < $TTL;
    $ttl = $MAX_TTL if $ttl > $MAX_TTL;
    return $ttl;
}

sub _homedir {
    return $Cpanel::homedir || scalar( ( Cpanel::PwCache::getpwuid($>) )[7] );
}

sub _generate_delivery_event_file {
    my ( $homedir, $email_from, $email_to, $now, $max, $ttl ) = @_;

    my $counter = 0;

    my $fh;
    while ( !sysopen( $fh, "$homedir/.cpanel/mailloopprotect/$email_from/$email_to/${now}-" . $counter++, $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_EXCL | $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_APPEND )
        && $counter < $max ) {

        # failed to write
    }

    # Fail only if the last attempt to create a file failed because it was already in place.
    return if $counter == $max and $!{EEXIST};
    if ($fh) {
        print {$fh} $ttl if defined $ttl;    # empty file means use global default
        close $fh;                           # fail ok
    }
    return 1;
}

# so it may be mocked in unit tests
sub _time { time }

1;
