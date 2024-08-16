package Cpanel::FileUtils::Copy;

# cpanel - Cpanel/FileUtils/Copy.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Fcntl            ();
use Cpanel::Fcntl::Constants ();
use Cpanel::LoadModule       ();
use Cpanel::Debug            ();

our $VERSION = '1.0';

my $COPY_CHUNK_SIZE = 131072;    #2 ** 17

sub safecopy {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my $srcfile    = shift;
    my $destfile   = shift;
    my $normrfcomp = shift || 0;

    if ( !length $srcfile ) {
        Cpanel::Debug::log_warn("Source not specified for copy.");
        return 0;
    }
    if ( !length $destfile ) {
        Cpanel::Debug::log_warn("Destination not specified for copy.");
        return 0;
    }
    if ( !-r $srcfile && $srcfile !~ m/\*$/ ) {
        Cpanel::Debug::log_warn("Unable to read source for copy");
        return 0;
    }

    my $is_file        = -f $srcfile ? 1 : 0;
    my $srcfileinfo    = q{};
    my $unlinkdestsafe = 1;
    if ($is_file) {    # Logic only for src files (not dirs).
                       # combination of device and inode
        $srcfileinfo = join( '-', ( stat(_) )[ 0, 1 ] );

        # '9' is an arbitrary int to indicate src file (not dir) exists
        $unlinkdestsafe = 9;
    }

    my $src_lock;
    if ($is_file) {

        #Try to lock the source file, though there’s no guarantee that we
        #will be able to since we may not have permission.
        local $@;
        require Cpanel::SafeFile;
        $src_lock = eval { Cpanel::SafeFile::safelock_skip_dotlock_if_not_root($srcfile) };
    }

    if ( !exists $INC{'File/Copy/Recursive.pm'} ) {
        Cpanel::LoadModule::lazy_load_module('File::Copy::Recursive');
    }
    if ( !exists $INC{'Cpanel/Umask.pm'} ) {
        Cpanel::LoadModule::lazy_load_module('Cpanel::Umask');
    }

    my $usefilecopyrecursive = ( exists $INC{'File/Copy/Recursive.pm'} && exists $INC{'Cpanel/Umask.pm'} ) ? 1 : 0;

    if ( !$usefilecopyrecursive ) {
        my $val = system( 'cp', '-rf', $srcfile, $destfile );
        if ($is_file) { Cpanel::SafeFile::safeunlock($src_lock) }
        if ($val) {
            Cpanel::Debug::log_warn("Problem copying $srcfile to $destfile! : system = $val");
            return 0;
        }
        return 1;
    }

    # destfile could be a dir, src file would be placed inside dir
    if ( $srcfileinfo ne '' && -f $destfile ) {
        my $destfileinfo = join( '-', ( stat(_) )[ 0, 1 ] );
        if ( $srcfileinfo eq $destfileinfo ) {    # files are the same
            Cpanel::SafeFile::safeunlock($src_lock) if $is_file;
            Cpanel::Debug::log_info("safecopy for $srcfile -> $destfile skipped. Target exists and has same size and inode number.");
            return 1;
        }

        if ( $unlinkdestsafe == 9 && !unlink($destfile) ) {

            # can't unlink (base dir probably immutable), disable unlinking altogether.
            # this specifically addresses Trustix chroot etc dir being immutable
            $unlinkdestsafe = 0;
        }
        else {

            # unlinking works, allow option to pass to File::Copy::Recursive (won't matter)
            $unlinkdestsafe = 1;
        }
    }
    else {

        # default to unlinking target as either srcfile is a dir or destfile doesn't exist.
        $unlinkdestsafe = 1;
    }

    # remove existing target file (not directory) first or warn
    # 0 = off, 1 = warn, 2 = return
    {
        no warnings;
        $File::Copy::Recursive::RMTrgFil = $unlinkdestsafe;
    }

    # Emulate 'cp -rf' for dirs.
    if ( !$normrfcomp ) {
        $File::Copy::Recursive::CPRFComp = 1;
    }
    else {
        $File::Copy::Recursive::CPRFComp = 0;
    }

    undef $!;
    my $umask_obj = Cpanel::Umask->new(077);

    if ( File::Copy::Recursive::rcopy( $srcfile, $destfile ) ) {
        if ( $is_file && $src_lock ) { Cpanel::SafeFile::safeunlock($src_lock) }
        return 1;
    }
    else {
        my $err_msg;
        my $err_no;

        # Use system error message set by File::Copy::Recursive
        if ($!) {
            $err_no  = int $!;
            $err_msg = "$!";
        }

        # This is completely arbitrary. Need Errno::EUNKNOWN but doesn't exist
        else {
            $err_no  = 85;
            $err_msg = 'Unknown copy failure';
        }

        if ( $is_file && $src_lock ) {
            Cpanel::SafeFile::safeunlock($src_lock);
        }

        Cpanel::Debug::log_warn(qq{rcopy('$srcfile', '$destfile') failed: $err_msg});
        $! = $err_no;    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
        return wantarray ? ( 0, $err_msg ) : 0;
    }
}

#Use this when race safety is not a concern.
#Args in can be either paths or filehandles/globrefs.
#NOTE: If you pass in filehandles, any read/write/close errors will be nonsensical!
#Two-argument return format.
sub copy {
    my ( $source, $destination ) = @_;

    local $!;

    my ( $rfh, $wfh );

    my ( $i_opened_the_source, $i_opened_the_destination );

    if ( UNIVERSAL::isa( $source, 'GLOB' ) ) {
        if ( !fileno $source ) {
            return ( 0, "The source file handle is not open." );
        }
        elsif ( fcntl( $source, $Cpanel::Fcntl::Constants::F_GETFL, 0 ) & 1 ) {
            return ( 0, "The source file handle is write-only." );
        }

        $rfh = $source;
    }
    else {
        $i_opened_the_source = 1;

        open( $rfh, '<', $source ) or do {
            return ( 0, "The system failed to open the file “$source” for reading because of an error: $!" );
        };
    }

    my $buffer;
    read $rfh, $buffer, $COPY_CHUNK_SIZE or do {
        if ( length $! ) {
            return ( 0, "The system failed to read from the file “$source” because of an error: $!" );
        }
    };

    my $mode = ( stat $source )[2] & 07777;

    my $write_lock;

    if ( UNIVERSAL::isa( $destination, 'GLOB' ) ) {
        if ( !fileno $destination ) {
            return ( 0, "The destination file handle is not open." );
        }
        elsif ( !( fcntl( $destination, $Cpanel::Fcntl::Constants::F_GETFL, 0 ) & 1 ) ) {
            return ( 0, "The destination file handle is read-only." );
        }

        $wfh = $destination;
    }
    else {
        $i_opened_the_destination = 1;

        local $!;
        local $@;
        require Cpanel::SafeFile;
        $write_lock = eval { Cpanel::SafeFile::safesysopen( $wfh, $destination, Cpanel::Fcntl::or_flags(qw( O_WRONLY O_CREAT )), $mode ) } or do {
            return ( 0, "The system failed to open the file “$destination” for writing because of an error: " . ( $@ || $! ) );
        };
    }

    # FIXME: use syswrite/sysread
    do {

        #NOTE: Printing to $wfh seems to generate spurious failures
        #when $destination is a file handle (and $wfh is a copy of it).
        print {$wfh} $buffer or do {
            return ( 0, "The system failed to write to the file “$destination” because of an error: $!" );
        };
    } while read $rfh, $buffer, $COPY_CHUNK_SIZE;

    if ($!) {
        return ( 0, "The system failed to read from the file “$source” because of an error: $!" );
    }

    truncate( $wfh, tell($wfh) );
    if ($!) {
        return ( 0, "The system failed to truncate the file “$destination” because of an error: $!" );
    }

    if ($i_opened_the_destination) {
        Cpanel::SafeFile::safeclose( $wfh, $write_lock ) or do {
            return ( 0, "The system failed to close the file “$destination” because of an error: $!" );
        };
    }

    if ($i_opened_the_source) {
        close $rfh or do {
            return ( 0, "The system failed to close the file “$source” because of an error: $!" );
        };
    }

    return 1;
}

1;
