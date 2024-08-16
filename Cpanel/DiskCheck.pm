package Cpanel::DiskCheck;

# cpanel - Cpanel/DiskCheck.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception          ();
use Cpanel::Filesys::Info      ();
use Cpanel::Filesys::FindParse ();
use Cpanel::Sys::Hostname      ();

my $locale;
my $BLOCK_SIZE = 1024;

## case 20142: preemptive disk space check. We need space for compressed files plus their
##   extraction (assuming a worst case ratio, with a .tar.gz of binary files)
my %USAGE_RATIOS = (
    'gzip_compressed_tarball'  => 3,       # For gzip, we assume a semi-worst case compression ratio of 3.0 (original to compressed)
    'bzip2_compressed_tarball' => 2.75,    # For bzip2, we assume a semi-worst case compression ratio of 2.75 (original to compressed)
    'raw_copy'                 => 1,       # For raw copy, we assume that duplicating the files will use the same amount of space.
    'streamed'                 => 1,       # For streamed, we also assume that duplicating the files will use the same amount of space.
    'mailbox'                  => 1.15,    # maildir -> mdbox conversion requires 115% of the space
    'optimize_eximstats'       => 2,       # For scripts/optimize_eximstats - SQLite command VACUUM requires up to 2x db size see: https://sqlite.org/lang_vacuum.html
);

my %REQUIRED_SPACE_RATIO_MAP = (
    'raw_copy'                 => $USAGE_RATIOS{'raw_copy'},
    'uncompressed_tarball'     => $USAGE_RATIOS{'raw_copy'},                   #uncompressed
    'gzip_compressed_tarball'  => $USAGE_RATIOS{'gzip_compressed_tarball'},
    'bzip2_compressed_tarball' => $USAGE_RATIOS{'bzip2_compressed_tarball'},
    'streamed'                 => $USAGE_RATIOS{'streamed'},
    'mailbox'                  => $USAGE_RATIOS{'mailbox'},
    'optimize_eximstats'       => $USAGE_RATIOS{'optimize_eximstats'},
    'mysqlsize'                => $USAGE_RATIOS{'raw_copy'},
);

sub get_usage_type_from_filename {
    my ($filename) = @_;

    return ( $filename =~ m{\.bz2$} ? 'bzip2_compressed_tarball' : $filename =~ m{\.tar$} ? 'uncompressed_tarball' : 'gzip_compressed_tarball' );
}

sub get_dir_disk_usage {
    my ($path) = @_;

    #NOTE: This won’t detect multiply-linked files,
    #so if you have the same file hard linked multiple times,
    #that one file will be added to the bytes total multiple times.

    $path =~ tr{/}{}s;    # collapse duplicate /s

    if ( -l $path ) {
        require Cpanel::Readlink;
        $path = Cpanel::Readlink::deep($path);
    }

    my $bytes = 0;
    my $files = 0;
    require Cpanel::SafeFind;
    Cpanel::SafeFind::find(
        sub {
            $files++;
            $bytes += ( lstat($File::Find::name) )[7];
        },
        $path
    );

    return ( $bytes, $files );
}

###########################################################################
#
# Method:
#   target_on_host_has_enough_free_space_to_fit_source_sizes
#
# Description:
#   Determine if a path target on a given host has enough space to accommodate
#   data from a given source or list of source sizes
#
# Parameters:
#   'target'                  -  The path target to calculate needed space.
#   'host'                    -  The host where the path target is located.
#   'source_sizes'            -  The precalculated sizes of the source data.
#   'target_blocks_free'      -  The blocks free at the path target.
#   'target_inodes_free'      -  Optional: The inodes free at the path target.
#   'output_coderef'          -  Optional: A coderef used to display the output messages
#
#     The source_sizes argument is an arrayref of hashrefs with keys that values in the amount of the space required.
#
#     For example:
#      [ {'streamed' => 4096 }, {'bzip2_compressed_tarball' => 1000000}, {'gzip_compressed_tarball' => 3223232}, {'files'=>9999999} ]
#
#     This would represent 4096 bytes of streamed data, 1000000 bytes of bzip2 compressed tarball data,
#     and 3223232 bytes of gzip compressed tarball data that would be copied to the target.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter   - Thrown if one of the required paramters is missing.
#
# Returns:
#   Two argument return
#     First:  1 - There is sufficient disk space, 0 - There is insufficient disk space.
#     Second: If the first argument is 0, a localized string explaining how much space is needed and how much space is available.
#
# NOTE: This function only manipulates memory; everything it knows about
# disk space/usage is given to it.
#
sub target_on_host_has_enough_free_space_to_fit_source_sizes {
    my (%OPTS) = @_;

    _required_params( \%OPTS, [ 'target', 'source_sizes', 'host' ] );

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'target_blocks_free' ] ) if !length $OPTS{'target_blocks_free'};    # can be zero
    my $target         = $OPTS{'target'};
    my $host           = $OPTS{'host'};
    my $output_coderef = $OPTS{'output_coderef'} || \&generic_output;
    my $source_sizes   = $OPTS{'source_sizes'};

    my $needed_size = _compute_needed_sizes($source_sizes);
    my $free_size   = ( $OPTS{'target_blocks_free'} * $BLOCK_SIZE );

    $output_coderef->( _locale()->maketext( "Target “[_1]” on host “[_2]” has [format_bytes,_3] free and requires at least [format_bytes,_4] free, which includes space for temporary files.", $target, $host, $free_size, $needed_size ) . "\n" );

    if ( $free_size < $needed_size ) {
        return ( 0, _locale()->maketext( "Insufficient disk space is available. “[_1]” on host “[_2]” has [format_bytes,_3] free and requires at least [format_bytes,_4] free, which includes space for temporary files.", $target, $host, $free_size, $needed_size ) );
    }

    if ( _has_inodes_info($source_sizes) ) {
        my $needed_files = _compute_needed_files($source_sizes);
        my $free_files   = $OPTS{'target_inodes_free'};
        if ( $needed_files && length $free_files ) {
            $output_coderef->( _locale()->maketext( "Target “[_1]” on host “[_2]” has [quant,_3,inode,inodes] free and requires at least [quant,_4,inode,inodes] free, which includes space for temporary files.", $target, $host, $free_files, $needed_files ) . "\n" );

            if ( $free_files < $needed_files ) {
                return ( 0, _locale()->maketext( "Insufficient disk space is available to perform the transfer. “[_1]” on host “[_2]” has [quant,_3,inode,inodes] free and requires at least [quant,_4,inode,inodes] free, which includes space for temporary files.", $target, $host, $free_files, $needed_files ) );
            }
        }
    }

    return ( 1, 'ok' );

}

###########################################################################
#
# Method:
#   target_has_enough_free_space_to_fit_source_sizes
#
# Description:
#   Determine if a path target has enough space to accommodate data from
#   a given source or list of source sizes
#
# Parameters:
#   'target'                  -  The path target to calculate needed space.
#   'source_sizes'            -  The precalculated sizes of the source data.
#   'output_coderef'          -  Optional: A coderef used to display the output messages
#
#     The source_sizes argument is an arrayref of hashrefs with keys that values in the amount of the space required.
#
#     For example:
#      [ {'streamed' => 4096 }, {'bzip2_compressed_tarball' => 1000000}, {'gzip_compressed_tarball' => 3223232} ]
#
#     This would represent 4096 bytes of streamed data, 1000000 bytes of bzip2 compressed tarball data,
#     and 3223232 bytes of gzip compressed tarball data that would be copied to the target.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter   - Thrown if one of the required paramters is missing.
#
# Returns:
#   Two argument return
#     First:  1 - There is sufficient disk space, 0 - There is insufficient disk space.
#     Second: If the first argument is 0, a localized string explaining how much space is needed and how much space is available.
#
#TODO: Make error reporting distinguish between an actual *failure*
#versus when we successfully determined that there is not enough space.
#
sub target_has_enough_free_space_to_fit_source_sizes {
    my (%OPTS) = @_;

    _required_params( \%OPTS, [ 'target', 'source_sizes' ] );

    my ( $target_blocks_free, $target_inodes_free ) = _get_mount_point_free_blocks_and_inodes_by_path( $OPTS{'target'} );

    return target_on_host_has_enough_free_space_to_fit_source_sizes(
        'host'               => Cpanel::Sys::Hostname::gethostname(),    #
        'target'             => $OPTS{'target'},                         #
        'source_sizes'       => $OPTS{'source_sizes'},                   #
        'target_blocks_free' => $target_blocks_free,                     #
        'target_inodes_free' => $target_inodes_free,                     #
        'output_coderef'     => $OPTS{'output_coderef'}                  #
    );
}

###########################################################################
#
# Method:
#   target_has_enough_free_space_to_fit_source
#
# Description:
#   Determine if a path target has enough space to accommodate data from
#   a given source or list of source sizes
#
# Parameters:
#   'target'                  -  The path target to calculate needed space.
#   'source'                  -  The path to the source of the data (Can be a tarball or directory).
#   'output_coderef'          -  Optional: A coderef used to display the output messages
#
# Exceptions:
#   Cpanel::Exception::MissingParameter   - Thrown if one of the required paramters is missing.
#
# Returns:
#   Two argument return
#     First:  1 - There is sufficient disk space, 0 - There is insufficient disk space.
#     Second: If the first argument is 0, a localized string explaining how much space is needed and how much space is available.
#
#TODO: Make error reporting distinguish between an actual *failure*
#versus when we successfully determined that there is not enough space.
#
sub target_has_enough_free_space_to_fit_source {
    my (%OPTS) = @_;

    _required_params( \%OPTS, [ 'target', 'source' ] );

    my $output_coderef = $OPTS{'output_coderef'} || \&generic_output;

    $output_coderef->( _locale()->maketext('Calculating disk space needed …') );
    my $source_sizes = calculate_source_sizes( $OPTS{'source'} );
    $output_coderef->( _locale()->maketext('Done.') . "\n" );

    return target_has_enough_free_space_to_fit_source_sizes(
        'target'         => $OPTS{'target'},    #
        'source_sizes'   => $source_sizes,      #
        'output_coderef' => $output_coderef     #
    );
}

sub calculate_source_sizes {
    my ($source) = @_;

    #
    # This returns data in the format of 'source_sizes' as shown below:
    #
    # [ {'streamed' => 4096 }, {'bzip2_compressed_tarball' => 1000000}, {'gzip_compressed_tarball' => 3223232}, {'files'=>99999} ]
    #
    if ( -d $source ) {
        my ( $bytes, $files ) = get_dir_disk_usage($source);
        return [ { 'raw_copy' => $bytes }, { 'files' => $files } ];
    }
    else {
        return [
            {
                get_usage_type_from_filename($source) => ( stat($source) )[7] // undef,
            },
            { 'files' => 1 },
        ];
    }
}

sub generic_output {
    my ($str) = @_;

    return print $str;
}

sub blackhole_output { return; }

sub _locale {
    require Cpanel::Locale;
    return $locale ||= Cpanel::Locale->get_handle();
}

sub _has_inodes_info {
    my ($source_sizes_ar) = @_;
    for my $_size (@$source_sizes_ar) {
        if ( exists $_size->{'files'} and int( $_size->{'files'} ) > 1 ) {
            return 1;
        }
    }
    return;
}

sub _compute_needed_files {
    my ($source_sizes_ar) = @_;

    my $needed_files = 0;
    #
    # A source_sizes_ar looks like
    # [ {'streamed' => 4096 }, {'bzip2_compressed_tarball' => 1000000}, {'gzip_compressed_tarball' => 3223232}, {'files'=>99999999} ]
    #
    for my $_size (@$source_sizes_ar) {

        # In practice this loop only happens once.
        foreach my $key ( sort keys %{$_size} ) {
            next if $key ne 'files';
            $needed_files += ( $_size->{$key} || 1 );
        }
    }

    return $needed_files;

}

sub _compute_needed_sizes {
    my ($source_sizes_ar) = @_;

    my $needed_size = 0;
    #
    # A source_sizes_ar looks like
    # [ {'streamed' => 4096 }, {'bzip2_compressed_tarball' => 1000000}, {'gzip_compressed_tarball' => 3223232}, {'files'=>99999999} ]
    #
    for my $_size (@$source_sizes_ar) {

        # In practice this loop only happens once.
        foreach my $key ( sort keys %{$_size} ) {
            next                                                 if $key eq 'files';
            die "Implementer error: unknown usage type: “$key”." if !exists $REQUIRED_SPACE_RATIO_MAP{$key};
            $needed_size += ( $_size->{$key} * $REQUIRED_SPACE_RATIO_MAP{$key} );
        }
    }

    return $needed_size;

}

sub _get_mount_point_free_blocks_and_inodes_by_path {
    my ($path) = @_;

    my $filesys_ref = Cpanel::Filesys::Info::_all_filesystem_info();
    my $mnt         = Cpanel::Filesys::FindParse::find_mount( $filesys_ref, $path );
    my $info        = $filesys_ref->{$mnt};

    # inodes must be a zero length string if there is no data to avoid failing when we just do not have an inode limit
    #
    return ( $info->{'blocks_free'} || 0, $info->{'inodes_free'} || '' );

}

sub _required_params {
    my ( $opts_ref, $required_ref ) = @_;

    foreach my $param ( @{$required_ref} ) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $param ] ) if !$opts_ref->{$param};
    }

    return 1;
}

1;
