package Cpanel::ZoneFile::Transaction;

# cpanel - Cpanel/ZoneFile/Transaction.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# Race safety is not feasible with zone files, but we still lock on both
# read and write to guard against partial reads/writes.
#----------------------------------------------------------------------

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Try::Tiny;

use Cpanel::Fcntl::Constants             ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Transaction::File::Raw       ();
use Cpanel::AdminBin::Serializer         ();
use Cpanel::FileUtils::Write::JSON::Lazy ();
use Cpanel::ZoneFile::Versioning         ();
use Cpanel::Encoder::URI                 ();
use Errno                                ();

use constant {
    _VERSION     => '4.1',
    _CACHE_DIR   => 'cache',
    _MAX_FUTURE  => 1200,      # Handle a maximum of 1200/zone changes per second.
    _CACHE_PERMS => 0600,
};

sub write_zone_file {
    my ( $zonedir, $zone, $zonedata ) = @_;

    my ( $path, $file, $cachefile ) = _path_file_cachefile_from_zonedir_and_zone( $zonedir, $zone );
    my $now = _time();

    my $trans = Cpanel::Transaction::File::Raw->new( 'path' => $path );

    _ensure_stringref_ends_in_newline( \$zonedata );
    _update_version_line( \$zonedata, $now );
    $trans->set_data( \$zonedata );
    my $data = _generate_zonecache_from_zoneref( \$zonedata, $zone, $now );
    _write_cachefile( $cachefile, $data );

    # BIND will only reload a zone if the mtime it cached
    # from the zone INCREASES.  This means we need to ensure
    # the mtime increases on the file every time we modify it
    # in order to ensure that the next BIND reload will pick it up.
    # Sometimes that means we are forced to set a FUTURE mtime.
    #
    $trans->save_or_die(
        minimum_mtime => 1 + $trans->get_mtime(),
    );

    my $final_mtime = $trans->get_mtime();
    utime( $final_mtime, $final_mtime, $cachefile ) or do {
        warn "utime($cachefile): $!";
    };

    $trans->close_or_die();

    return;
}

sub _write_cachefile {
    my ( $cachefile, $data ) = @_;

    Cpanel::FileUtils::Write::JSON::Lazy::write_file( $cachefile, $data, _CACHE_PERMS() );

    return;
}

sub read_zone_file {
    my ( $zonedir, $zone ) = @_;

    my ( $path, $file, $cachefile ) = _path_file_cachefile_from_zonedir_and_zone( $zonedir, $zone );
    my $now = _time();

    #We need to stat($path) one way or another.
    my $path_mtime = ( stat($path) )[9] or do {

        # Report here so we do not report a lock error
        die "stat($file) failed: $!";
    };

    if ( open my $cache_fh, '<', $cachefile ) {
        my $cache_fh_mtime = ( stat($cache_fh) )[9];
        if ( $cache_fh_mtime <= $now + _MAX_FUTURE() && $cache_fh_mtime >= $path_mtime ) {    # check after we are open to avoid possible race condition

            #We don’t care about the failure here; we’ll just regenerate
            #the cache file below.
            local $@;
            my $data = eval {
                local $SIG{'__WARN__'};
                Cpanel::AdminBin::Serializer::LoadFile($cache_fh);
            };
            if ($data) {
                my $ok = !!$data->{'zonedata'};
                $ok &&= $data->{'version'} eq _VERSION();
                return $data if $ok;
            }
        }

        #shouldn’t fail, but just in case
        close $cache_fh or warn "close($cachefile): $!";
    }
    elsif ( $! != Errno::ENOENT() ) {
        warn "open($cachefile): $!";
    }

    #----------------------------------------------------------------------
    # There’s no valid cache, so we read the zone file afresh.
    # We lock here to ensure that we write out a valid cache file.
    # TODO: This could be done with a read lock.
    #----------------------------------------------------------------------

    my $trans        = Cpanel::Transaction::File::Raw->new( 'path' => $path, 'sysopen_flags' => $Cpanel::Fcntl::Constants::O_RDONLY );
    my $mtime        = $trans->get_mtime();
    my $zonedata_ref = $trans->get_data();
    _ensure_stringref_ends_in_newline($zonedata_ref);
    my $data = _generate_zonecache_from_zoneref( $zonedata_ref, $zone, $mtime );

    _write_cachefile( $cachefile, $data );

    $trans->close_or_die();

    return $data;
}

sub _time {    # for mocking
    return time();
}

sub _path_file_cachefile_from_zonedir_and_zone {
    my ( $zonedir, $zone ) = @_;

    #Cpanel::Validate::Domain is expensive. We should have checked the zone
    #already. This is just a last-minute security check.
    Cpanel::Validate::FilesystemNodeName::validate_or_die($zone);

    my $file      = $zone . '.db';
    my $cachefile = "$zonedir/" . _CACHE_DIR() . "/$file";
    my $path      = "$zonedir/$file";
    return ( $path, $file, $cachefile );
}

sub _generate_zonecache_from_zoneref {
    my ( $zonedata_ref, $zone, $mtime ) = @_;
    return {
        'zonedata'         => $$zonedata_ref,
        'encoded_zonedata' => Cpanel::Encoder::URI::uri_encode_str($$zonedata_ref),
        'zone'             => $zone,
        'mtime'            => $mtime,
        'encoded_zone'     => Cpanel::Encoder::URI::uri_encode_str($zone),
        'version'          => _VERSION(),
    };
}

sub _update_version_line {
    my ( $zone_data_ref, $mtime ) = @_;

    my $current_version_line;
    if ( $$zone_data_ref =~ /^(\s*;\s*cPanel[^\n]+)\n/ ) {
        $current_version_line = $1;
        substr( $$zone_data_ref, 0, length($current_version_line) + 1, '' );
    }

    my $version_line = Cpanel::ZoneFile::Versioning::version_line( $current_version_line || '', $mtime );

    _ensure_stringref_ends_in_newline( \$version_line );

    substr( $$zone_data_ref, 0, 0, $version_line );

    return 1;
}

sub _ensure_stringref_ends_in_newline {
    my ($str_ref) = @_;

    if ( substr( $$str_ref, -1, 1 ) ne "\n" ) {
        $$str_ref .= "\n";
    }

    return 1;
}

1;
