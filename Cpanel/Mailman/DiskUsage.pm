package Cpanel::Mailman::DiskUsage;

# cpanel - Cpanel/Mailman/DiskUsage.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Mailman::Filesys             ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::LoadModule                   ();
use Cpanel::FileUtils::Write             ();
use Cpanel::AdminBin::Serializer         ();
use Cpanel::AdminBin::Serializer::FailOK ();
use Time::Local                          ();

my $CACHE_OBJECT_SIZE          = 0;
my $CACHE_OBJECT_MTIME         = 1;
my $CACHE_OBJECT_CHILDREN_SIZE = 2;

sub get_mailman_archive_dir_disk_usage {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my $list = shift;
    my $data_ref;
    my $now = time();

    Cpanel::SafeDir::MK::safemkdir('/var/cpanel/mailman/diskusage_cache') if !-d '/var/cpanel/mailman/diskusage_cache';    #FIXME: check for failure

    $data_ref = Cpanel::AdminBin::Serializer::FailOK::LoadFile( '/var/cpanel/mailman/diskusage_cache/' . $list . '_archives.cache' );

    if ( !$data_ref || ( $data_ref->{'last_reset_time'} || 0 ) + ( 86400 * 30 ) < $now ) {

        # The cache is only valid for 30 days in case something gets changed under us
        $data_ref = {};
        $data_ref->{'last_reset_time'} = $now;
    }
    $data_ref->{'mtime'} = $now;
    my $total_size = 0;

    my $MAILMAN_ARCHIVE_DIR = Cpanel::Mailman::Filesys::MAILMAN_ARCHIVE_DIR();

    #   {'dirs'}[ 0 = Size of object, 1 = mtime of object, 2 = size of children ]
    if ( opendir( my $private_dir, "$MAILMAN_ARCHIVE_DIR/$list" ) ) {
        my @subdirs;
        my ( $size, $mtime );
        while ( my $file = readdir($private_dir) ) {
            next if ( $file eq '..' );
            $total_size += ( ( $size, $mtime ) = ( lstat("$MAILMAN_ARCHIVE_DIR/$list/$file") )[ 7, 9 ] )[0];
            next if ( !-d _ );
            if ( $file eq '.' || $file eq 'attachments' ) {
                $data_ref->{'dirs'}{$file} = [ $size, $mtime ];
            }
            elsif ( exists $data_ref->{'dirs'}{$file} && $data_ref->{'dirs'}{$file}->[$CACHE_OBJECT_MTIME] == $mtime && $data_ref->{'dirs'}{$file}->[$CACHE_OBJECT_SIZE] == $size && defined $data_ref->{'dirs'}{$file}->[$CACHE_OBJECT_CHILDREN_SIZE] ) {

                # We can use the cached size of the children
                $total_size += $data_ref->{'dirs'}{$file}->[$CACHE_OBJECT_CHILDREN_SIZE];
            }
            else {

                # We need to calculate the size of the children in the next step
                # because it is not in the cache
                $data_ref->{'dirs'}{$file} = [ $size, $mtime ];
                push @subdirs, $file;
            }
        }
        close($private_dir);
        foreach my $subdir (@subdirs) {

            # We exclude the directory because it will be calcated above in the first loop
            # Since we calculate attachments below we skip these as well
            if ( opendir( my $private_sub_dir, "$MAILMAN_ARCHIVE_DIR/$list/$subdir" ) ) {
                while ( my $file = readdir($private_sub_dir) ) {
                    next if ( $file eq '..' || $file eq '.' );
                    $data_ref->{'dirs'}{$subdir}->[$CACHE_OBJECT_CHILDREN_SIZE] += ( lstat("$MAILMAN_ARCHIVE_DIR/$list/$subdir/$file") )[7];
                }
            }
            $total_size += $data_ref->{'dirs'}{$subdir}->[$CACHE_OBJECT_CHILDREN_SIZE] // 0;
        }
        if ( opendir( my $attachments_sub_dir, "$MAILMAN_ARCHIVE_DIR/$list/attachments" ) ) {
            while ( my $dir = readdir($attachments_sub_dir) ) {
                next if ( $dir eq '..' || $dir eq '.' || length $dir < 8 );
                if ( exists $data_ref->{'dirs'}{ 'attachments/' . $dir } ) {
                    my ( $year, $mon, $mday ) = ( substr( $dir, 0, 4 ), substr( $dir, 4, 2 ), substr( $dir, 6, 2 ) );
                    next if !$year || !$mon || !$mday || $year =~ tr{0-9}{}c || $mon =~ tr{0-9}{}c || $mday =~ tr{0-9}{}c;
                    my $dir_timestamp = Time::Local::timelocal_modern( 0, 0, 0, $mday, $mon - 1, $year );

                    # We can use the cache for this dir as we know it will not change because of the name
                    if ( $dir_timestamp + 86400 < $now ) {
                        $total_size += $data_ref->{'dirs'}{ 'attachments/' . $dir }->[$CACHE_OBJECT_SIZE] + $data_ref->{'dirs'}{ 'attachments/' . $dir }->[$CACHE_OBJECT_CHILDREN_SIZE];
                        $data_ref->{'dirs'}{'attachments'}->[$CACHE_OBJECT_CHILDREN_SIZE] += $data_ref->{'dirs'}{ 'attachments/' . $dir }->[$CACHE_OBJECT_SIZE] + $data_ref->{'dirs'}{ 'attachments/' . $dir }->[$CACHE_OBJECT_CHILDREN_SIZE];
                        next;
                    }
                }
                my ( $size, $mtime ) = ( lstat("$MAILMAN_ARCHIVE_DIR/$list/attachments/$dir") )[ 7, 9 ];
                my $dir_size = 0;
                Cpanel::LoadModule::load_perl_module('Cpanel::SafeFind') if !$INC{'Cpanel/SafeFind.pm'};
                Cpanel::SafeFind::find(
                    sub {
                        $dir_size += ( lstat($File::Find::name) )[7];
                    },
                    "$MAILMAN_ARCHIVE_DIR/$list/attachments/$dir"
                );
                $data_ref->{'dirs'}{ 'attachments/' . $dir } = [ $size, $mtime, ( $dir_size - $size ) ];
                $data_ref->{'dirs'}{'attachments'}->[$CACHE_OBJECT_CHILDREN_SIZE] += $dir_size;
                $total_size += $dir_size;
            }
        }
    }
    else {
        warn "Could not open archive dir for $list: $!";
    }

    Cpanel::FileUtils::Write::overwrite( '/var/cpanel/mailman/diskusage_cache/' . $list . '_archives.cache', Cpanel::AdminBin::Serializer::Dump($data_ref), 0600 );

    return $total_size;
}

sub get_mailman_list_dir_disk_usage {
    my $list       = shift;
    my $total_size = 0;

    my $list_dir = Cpanel::Mailman::Filesys::get_list_dir($list);

    if ( opendir( my $list_dh, $list_dir ) ) {
        while ( my $file = readdir($list_dh) ) {
            next if ( $file eq '..' );
            $total_size += ( lstat("$list_dir/$file") )[7];
        }
        close($list_dir);
    }
    else {
        warn "Could not open list dir for $list: $!";
    }
    return $total_size;
}

sub get_mailman_archive_dir_mbox_disk_usage {
    my $list                = shift;
    my $total_size          = 0;
    my $MAILMAN_ARCHIVE_DIR = Cpanel::Mailman::Filesys::MAILMAN_ARCHIVE_DIR();
    if ( opendir( my $archive_mbox_dir, "$MAILMAN_ARCHIVE_DIR/$list.mbox" ) ) {
        while ( my $file = readdir($archive_mbox_dir) ) {
            next if ( $file eq '..' );
            $total_size += ( lstat("$MAILMAN_ARCHIVE_DIR/$list.mbox/$file") )[7];
        }
        close($archive_mbox_dir);
    }
    else {
        warn "Could not open archive mbox dir for $list: $!";
    }
    return $total_size;
}

1;
