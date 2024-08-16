package Cpanel::SafeFile::Replace;

# cpanel - Cpanel/SafeFile/Replace.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Fcntl::Constants ();
use Cpanel::FileUtils::Open  ();
use File::Basename           ();

use constant {
    WRONLY_CREAT_EXCL => $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_EXCL,
    _EEXIST           => 17
};

sub safe_replace_content {
    my ( $fh, $safelock, @content ) = @_;

    return locked_atomic_replace_contents(
        $fh,
        $safelock,
        sub {
            local $!;

            @content = @{ $content[0] } if scalar @content == 1 && ref $content[0] eq 'ARRAY';

            print { $_[0] } @content;

            if ($!) {
                my $length = 0;
                $length += length for @content;

                my $err = $!;
                require Cpanel::Exception;
                die Cpanel::Exception::create( 'IO::WriteError', [ length => $length, error => $err ] );
            }

            return 1;
        }
    );
}

my $_lock_ex_nb;

sub locked_atomic_replace_contents {
    my ( $fh, $safelock, $coderef ) = @_;

    $_lock_ex_nb //= $Cpanel::Fcntl::Constants::LOCK_EX | $Cpanel::Fcntl::Constants::LOCK_NB;
    if ( !flock $fh, $_lock_ex_nb ) {
        my $err = $!;
        require Cpanel::Exception;
        die Cpanel::Exception::create_raw( 'IOError', "locked_atomic_replace_contents could not lock the file handle because of an error: $err" );
    }

    if ( !ref $safelock ) {
        local $@;
        if ( !eval { $safelock->isa('Cpanel::SafeFileLock') } ) {
            die "locked_atomic_replace_contents requires a Cpanel::SafeFileLock object";
        }
    }

    my $locked_path = $safelock->get_path_to_file_being_locked();
    die "locked_path must be valid" if !length $locked_path;
    my ( $temp_file, $temp_fh, $created_temp_file, $attempts );
    my $current_perms = ( stat($fh) )[2] & 07777;

    while ( !$created_temp_file && ++$attempts < 100 ) {
        $temp_file = sprintf(
            '%s-%x-%x-%x',
            $locked_path,
            substr( rand, 2 ),
            scalar( reverse time ),
            scalar( reverse $$ ),
        );

        # The maximum length for a file name is 255 bytes.
        # Ensure the temp filename length does not exceed this since domain names can be 254 characters
        # and Cpanel::ZoneFile::Transaction::write_zone_file is one of the callers of this sub
        my ( $basename, $dirname );
        $basename = File::Basename::basename($temp_file);
        if ( length $basename >= 255 ) {
            $basename  = substr( $basename, 255 );
            $dirname   = File::Basename::dirname($temp_file);
            $temp_file = "$dirname/$basename";
        }

        $created_temp_file = Cpanel::FileUtils::Open::sysopen_with_real_perms( $temp_fh, $temp_file, WRONLY_CREAT_EXCL, $current_perms ) or do {
            last if $! != _EEXIST;
        };
    }
    if ( !$created_temp_file ) {
        my $lasterr = $!;
        die Cpanel::Exception::create( 'TempFileCreateError', [ path => $temp_file, error => $lasterr ] );
    }

    if ( !flock $temp_fh, $Cpanel::Fcntl::Constants::LOCK_EX ) {
        my $err = $!;
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'IO::FlockError', [ path => $temp_file, error => $err, operation => $Cpanel::Fcntl::Constants::LOCK_EX ] );
    }

    select( ( select($temp_fh), $| = 1 )[0] );    ##no critic qw(ProhibitOneArgSelect Variables::RequireLocalizedPunctuationVars)  #aka $fd->autoflush(1);
    if ( $coderef->( $temp_fh, $temp_file, $current_perms ) ) {
        rename( $temp_file, $locked_path );
        return $temp_fh;
    }
    local $!;
    close $temp_fh;
    unlink $temp_file;
    die "locked_atomic_replace_contents coderef returns false";
}

1;
