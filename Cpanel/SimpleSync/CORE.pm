package Cpanel::SimpleSync::CORE;

# cpanel - Cpanel/SimpleSync/CORE.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie          ();
use Cpanel::Context          ();
use Cpanel::Lchown           ();
use Cpanel::Fcntl::Constants ();

use constant {
    _COPY_FLAGS             => $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_TRUNC | $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_NOFOLLOW,
    _COPY_FLAGS_NOOVERWRITE => $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_TRUNC | $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_NOFOLLOW | $Cpanel::Fcntl::Constants::O_EXCL,
    _READ_FLAGS             => $Cpanel::Fcntl::Constants::O_RDONLY,
    _READ_FLAGS_NOFOLLOW    => $Cpanel::Fcntl::Constants::O_RDONLY | $Cpanel::Fcntl::Constants::O_NOFOLLOW
};

our $CHOWN    = 0;
our $NO_CHOWN = 1;

our $FOLLOW_SYMLINKS = 0;
our $NO_SYMLINKS     = 1;

our $NO_RESUME = 0;
our $RESUMABLE = 1;

our $sync_contents_check = 1;

# syncfile - source, destination [, no_symlinks]
#    Given source and dest, if source's mtime is greater than that
#    of dest's, source will be copied over dest.
# Return Values:  0 - Problem copying.
#                -1 - File not copied,
#                 1 - File copied.
#                 2 - File copied (resumed).
sub syncfile {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $source, $dest, $no_sym, $no_chown, $resume ) = @_;

    Cpanel::Context::must_be_list();

    return ( -1, "Source file $source does not exist" ) if ( !-e $source );

    my ( $mode, $uid, $gid, $s_size, $s_mod ) = ( stat(_) )[ 2, 4, 5, 7, 9 ];

    if ( !defined($no_sym) )   { $no_sym   = 0; }
    if ( !defined($no_chown) ) { $no_chown = 0; }

    if ( -d $dest ) {
        $dest =~ s{/$}{}g;
        my @SRC = split( /\//, $source );
        $dest .= '/' . $SRC[$#SRC];
        undef @SRC;
        stat($dest);    # if we change files we need to stat it again as we use the stat cache below
    }

    my ( $d_mod, $d_size, $d_mode, $d_uid, $d_gid );
    if ( !-e _ ) {
        $d_mode = $d_mod = $d_size = 0;
        $d_uid  = $d_gid = -1;
    }
    else {
        ( $d_mode, $d_uid, $d_gid, $d_size, $d_mod ) = ( stat(_) )[ 2, 4, 5, 7, 9 ];
    }

    ## Determine if update required
    # Check if files have differing modes or sizes
    my $needs_update = ( $s_mod != $d_mod || $d_size != $s_size ) ? 1 : 0;

    # If mode and size are same, check file contents
    if ( $sync_contents_check && !$needs_update ) {
        if ( open( my $src_fh, '<', $source ) ) {
            if ( open( my $dest_fh, '<', $dest ) ) {
                my ( $src_buffer, $dest_buffer );
                while ( read( $src_fh, $src_buffer, 65535 ) ) {
                    if ( !read( $dest_fh, $dest_buffer, 65535 ) || $src_buffer ne $dest_buffer ) {
                        $needs_update = 1;
                        last;
                    }
                }

                # Files are identical
                close $dest_fh;
            }
            close $src_fh;
        }
        else {
            warn "Failed to open source file “$source”: $!";
            $needs_update = 1;
        }
    }

    if ( $needs_update && $resume && $d_size < $s_size && $d_size > 4096 ) {    #resume allowed
        if ( open( my $src_fh, '<', $source ) ) {
            if ( open( my $dest_fh, '+<', $dest ) ) {
                my ( $src_buffer, $dest_buffer, $buffer );
                if ( seek( $dest_fh, $d_size - 4096, 0 ) && seek( $src_fh, $d_size - 4096, 0 ) && read( $dest_fh, $dest_buffer, 4096 ) == read( $src_fh, $src_buffer, 4096 ) && $dest_buffer eq $src_buffer ) {
                    seek( $src_fh,  $d_size, 0 );
                    seek( $dest_fh, $d_size, 0 );
                    while ( read( $src_fh, $buffer, 65535 ) ) {
                        print {$dest_fh} $buffer;
                    }

                    $needs_update = 2;
                }
                close $dest_fh;
            }
            close $src_fh;
        }
    }

    if ( $needs_update == 1 ) {
        my ( $status, $message ) = copy( $source, $dest, $mode & 07777, $no_sym );
        if ($status) {
            Cpanel::Lchown::lchown( $uid, $gid, $dest ) if !$no_chown;

            chmod $mode & 07777, $dest or do {
                warn "Failed to chmod($dest): $!";
            };

            utime( time, $s_mod, $dest );
        }
        return ( $status, $message );
    }
    else {
        Cpanel::Lchown::lchown( $uid, $gid, $dest ) if ( ( ( $d_uid != $uid ) || ( $d_gid != $gid ) ) && ( !$no_chown ) );

        chmod $mode & 07777, $dest or do {
            warn "Failed to chmod($dest): $!";
        };

        utime( time, $s_mod, $dest );
        return ( $needs_update, "$source -> $dest (resumed)" ) if $needs_update == 2;    #Resumed
        return ( -1,            "$source and $dest are up to date" );                    # Not Copied, but successful.
    }

    return ( 0, "Unknown failure syncing $source to $dest" );
}

# copy -
#   Params: Source file, Destination file.
#   Copies source to destination.
sub copy {
    my ( $source, $dest, $mode, $nofollow ) = @_;
    $mode ||= 0600;

    my $archive_dest;
    my $message;

    if ( sysopen my $from, $source, $nofollow ? _READ_FLAGS_NOFOLLOW : _READ_FLAGS ) {
        my $to;
        if ( !sysopen $to, $dest, _COPY_FLAGS_NOOVERWRITE, $mode ) {
            if ( -e $dest ) {
                $archive_dest = $dest . '.simplesync.' . time();
                rename( $dest, $archive_dest ) or do {
                    $message = "Failed to archive $dest: $!";
                    close $from;
                    return ( 0, $message );
                };
            }
            if ( !sysopen( $to, $dest, _COPY_FLAGS, $mode ) ) {
                $message = "Failed to safely open target $dest: $!";
                return ( 0, $message );
            }
        }
        my $buffer;
        local $@;
        eval {
            while ( Cpanel::Autodie::sysread_sigguard( $from, $buffer, 65535 ) ) {
                if ( !Cpanel::Autodie::syswrite_sigguard( $to, $buffer, length $buffer ) ) {
                    $message = "Failed to write buffer to $dest: $!";
                    last;
                }
            }
        };
        close $to;
        if ($@) {
            return ( 0, $@ );
        }
        close $from;
    }
    else {
        $message = "Failed to open: $source: $!";
    }

    if ( !$message ) {
        unlink $archive_dest if $archive_dest;
        return ( 1, "$source -> $dest" );
    }
    rename( $archive_dest, $dest ) if $archive_dest;
    return ( 0, $message );
}

1;
