package Cpanel::Quota;

# cpanel - Cpanel/Quota.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

# Do not use in as it will be included if needed
#use Cpanel                       ();
use Cpanel::CachedCommand::Valid ();
use Cpanel::Exception            ();
use Cpanel::LoadFile             ();
use Cpanel::Math                 ();
use Cpanel::Math::Bytes          ();
use Cpanel::PwCache              ();
use Cpanel::AdminBin::Serializer ();
use Cpanel::CachedCommand::Utils ();

use constant BLOCKS_TO_BYTES    => 1_024;
use constant MB                 => 1_024**2;
use constant GB                 => 1_024 * MB;
use constant MIN_SPACE_REQUIRED => 1 * MB;       # below that space, consider that user reached quota max.

=head1 NAME

Cpanel::Quota

=head1 SYNOPSIS

    use Cpanel::Quota ();

    my $info = Cpanel::Quota::getdiskinfo();

=head1 DESCRIPTION

Functions to check cPanel user quota.

=head1 FUNCTIONS

=cut

# Named constants for accessing the return from displayquota().
our $SPACE_USED   = 0;
our $SPACE_LIMIT  = 1;
our $SPACE_LEFT   = 2;
our $INODES_USED  = 3;
our $INODES_LIMIT = 4;
our $INODES_LEFT  = 5;

# This used to be /usr/bin/quota, however to avoid
# refactoring this module we mocked name was used.
my $MOCK_QUOTA_BINARY = '_Cpanel::Quota.pm_';

our $VERSION = '2.5';

our $QUOTA_NOT_ENABLED_STRING = 'NA' . "\n";    # New line is needed for legacy compat

my %quota_cache;

sub is_available {
    return ( _getspaceused_bytes() ne $QUOTA_NOT_ENABLED_STRING );
}

=head2 has_reached_quota()

Check if the account has reached the quota.
Returns a boolean:
- true when quota are reached (or very close to be)
- false when quota are disabled or user has enough disk space

=cut

sub has_reached_quota ( $user_specified_min_space_in_mb = undef ) {    # or close too
    return unless is_available();

    my $disk_info = getdiskinfo();

    return unless ref $disk_info && $disk_info->{spaceremain} =~ m{^\d+(\.\d+)?$}a;

    my $spaceremain = int( $disk_info->{spaceremain} );
    my $needs_space = MIN_SPACE_REQUIRED;

    if ($user_specified_min_space_in_mb) {
        $needs_space = $user_specified_min_space_in_mb * MB;
    }

    return $spaceremain < $needs_space;
}

sub die_if_has_reached_quota ( $needs_space_in_mb = undef ) {

    return unless has_reached_quota($needs_space_in_mb);

    die Cpanel::Exception::create('IO::DiskSpaceFull');
}

#This doesn't attempt to reset SQL or Mailman disk usage caches
#because the files that this module reads are caches themselves anyway.
sub reset_cache ( $user = undef ) {

    $user ||= Cpanel::PwCache::getpwuid($>);
    delete $quota_cache{$user};

    Cpanel::CachedCommand::Utils::invalidate_cache( $MOCK_QUOTA_BINARY, $user );

    # always clear the datastore for the current user
    _clear_datastore_file($user);

    return if $user eq 'root';

    # also clean it in the user home directory if possible (when root)
    if ( $> == 0 ) {
        require Cpanel::AccessIds;
        Cpanel::AccessIds::do_as_user(
            $user,
            sub {
                _clear_datastore_file($user);
                return;
            }
        );
    }

    return;
}

sub _clear_datastore_file ($user) {
    my $datastore_file = _datastore_file_for_user($user);
    return unlink($datastore_file);
}

sub _datastore_file_for_user ($user) {
    return Cpanel::CachedCommand::Utils::get_datastore_filename( $MOCK_QUOTA_BINARY, $user );
}

#Two forms:
#   ( $return_bytes boolean, $include_sqldbs boolean, $include_mailman boolean )
#   OR a single hash of: bytes, include_sqldbs, include_mailman, user
sub displayquota {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my $return_bytes    = shift;
    my $include_sqldbs  = shift;
    my $include_mailman = shift;

    my $user;

    if ( 'HASH' eq ref $return_bytes ) {
        ( $return_bytes, $include_sqldbs, $include_mailman, $user ) = @{$return_bytes}{qw(bytes include_sqldbs include_mailman user)};
    }

    $user ||= $Cpanel::user if $Cpanel::user;    # PPI NO PARSE - PwCache if no initcp
    $user ||= Cpanel::PwCache::getpwuid($>);

    if ( !defined($include_sqldbs) ) {
        $include_sqldbs = $Cpanel::CONF{'disk_usage_include_sqldbs'};    # PPI NO PARSE - passed in if no initcp
    }

    if ( !defined($include_mailman) ) {
        $include_mailman = $Cpanel::CONF{'disk_usage_include_mailman'};    # PPI NO PARSE - passed in if no initcp
    }

    my @parsed_quota;

    if ( $quota_cache{$user}{'parse'} ) {
        @parsed_quota = @{ $quota_cache{$user}{'parse'} };
    }
    else {
        my $datastore_file = _datastore_file_for_user($user);

        my ( $datastore_file_size, $datastore_file_mtime ) = ( stat($datastore_file) )[ 7, 9 ];
        my $quota_ref;
        if (
            Cpanel::CachedCommand::Valid::is_cache_valid(
                'datastore_file'       => $datastore_file,
                'datastore_file_mtime' => $datastore_file_mtime,
                'datastore_file_size'  => $datastore_file_size,
                'ttl'                  => _quota_ttl(),
                'mtime'                => _getquota_mtime(),
                'min_expire_time'      => _quota_min_expire_time(),
            )
        ) {
            # The below eval is not checked because the cache may
            # not exist or may be invalid and we will just fallback to
            # fetching the quota.
            eval { $quota_ref = Cpanel::AdminBin::Serializer::LoadFile($datastore_file); };
        }

        if ( $quota_ref && $quota_ref->{'VERSION'} == $VERSION ) {
            @parsed_quota = @{ $quota_ref->{'data'} };
        }
        else {
            require Cpanel::Quota::Common;
            my $quota_common_module = Cpanel::Quota::Common->new( { user => $user } );
            if ( !$quota_common_module->quotas_are_enabled() ) {
                return $QUOTA_NOT_ENABLED_STRING;
            }

            my $limits = try { $quota_common_module->get_limits(); };
            if ( !defined $limits ) {
                return $QUOTA_NOT_ENABLED_STRING;
            }

            my $inodes_soft_limit;
            my $inodes_used = 0;
            my $blocks_soft_limit;
            my $blocks_used = 0;

            for my $device ( sort keys %$limits ) {
                $inodes_soft_limit ||= $limits->{$device}{'inode'}{'soft'} || undef;
                $blocks_soft_limit ||= $limits->{$device}{'block'}{'soft'} || undef;
                $inodes_used += $limits->{$device}{'inode'}{'inodes'};
                $blocks_used += $limits->{$device}{'block'}{'blocks'};
            }

            my $blocks_remain = defined $blocks_soft_limit ? ( $blocks_soft_limit - $blocks_used ) : undef;
            my $inodes_remain = defined $inodes_soft_limit ? ( $inodes_soft_limit - $inodes_used ) : undef;
            $blocks_remain = 0 if defined $blocks_remain && $blocks_remain < 0;
            $inodes_remain = 0 if defined $inodes_remain && $inodes_remain < 0;

            $quota_ref = {
                'VERSION' => $VERSION,
                'data'    => [
                    $blocks_used * BLOCKS_TO_BYTES,
                    defined $blocks_soft_limit ? $blocks_soft_limit * BLOCKS_TO_BYTES : undef,
                    defined $blocks_remain     ? $blocks_remain * BLOCKS_TO_BYTES     : undef,
                    $inodes_used,
                    $inodes_soft_limit,
                    $inodes_remain,
                ]
            };

            require Cpanel::FileUtils::Write;
            try {
                Cpanel::FileUtils::Write::overwrite( $datastore_file, Cpanel::AdminBin::Serializer::Dump($quota_ref), 0600 );

            }
            catch {
                do {
                    local $@ = $_;
                    die;
                } unless ( try { $_->error_name() eq 'EDQUOT' } );
            };

            @parsed_quota = @{ $quota_ref->{'data'} };
        }
        $quota_cache{$user}{'parse'} = [@parsed_quota];
    }

    require Cpanel::UserDatastore;
    my $user_datastore_dir = Cpanel::UserDatastore::get_path($user);

    if ($include_sqldbs) {
        my $sqldbs_disk_usage = $quota_cache{$user}{'sqldbs_disk_usage_total'};
        if ( !defined($sqldbs_disk_usage) ) {

            my $mysql = int( Cpanel::LoadFile::loadfile("$user_datastore_dir/mysql-disk-usage")    || 0 );
            my $pgsql = int( Cpanel::LoadFile::loadfile("$user_datastore_dir/postgres-disk-usage") || 0 );
            $quota_cache{$user}{'sqldbs_disk_usage_total'} = $sqldbs_disk_usage = $mysql + $pgsql;
        }

        $parsed_quota[0] += $sqldbs_disk_usage;
    }

    if ($include_mailman) {
        my $mailman_disk_usage = $quota_cache{$user}{'mailman_disk_usage_total'};
        if ( !defined($mailman_disk_usage) ) {
            $quota_cache{$user}{'mailman_disk_usage_total'} = $mailman_disk_usage = int( Cpanel::LoadFile::loadfile("$user_datastore_dir/mailman-disk-usage") || 0 );
        }

        $parsed_quota[0] += $mailman_disk_usage;
    }

    if ( !$return_bytes ) {
        my $count = 0;
        @parsed_quota = map { $count++ >= 3 ? $_ : Cpanel::Math::Bytes::to_mib( $_ || 0 ) } @parsed_quota;
    }

    return @parsed_quota;
}

sub getdiskinfo {
    die "_getquota_mtime requires initcp first" if !$Cpanel::abshomedir;    # PPI NO PARSE - not called outside of initcp

    require Cpanel::Locale;
    my $locale = Cpanel::Locale->get_handle();
    my %RES;
    require Cpanel::Filesys::Info;
    my $fsinfo   = Cpanel::Filesys::Info::filesystem_info($Cpanel::abshomedir);
    my $diskfree = $fsinfo->{'blocks_free'} * 1024;

    # 0 = USED
    # 1 = LIMIT
    # 2 = REMAIN
    # 3 = FILESUSED
    # 4 = FILESLIMIT
    # 5 = FILESREMAIN
    #fetch these values in bytes
    my ( $quota_used, $quota_limit, $quota_remain, $files_used, $files_limit, $files_remain ) = displayquota(1);

    #for this, undef means zero anyway
    my $file_upload_must_leave_bytes = ( $Cpanel::CONF{'file_upload_must_leave_bytes'} || 0 ) * MB;    # PPI NO PARSE - not called outside of initcp

    #must be below ten gigs - tweaksettings checks for this, but just in case
    if ( $file_upload_must_leave_bytes > 10 * GB ) {
        $file_upload_must_leave_bytes = 5 * MB;
    }

    my $file_upload_max_bytes;
    if (
        exists $Cpanel::CONF{'file_upload_max_bytes'}       # PPI NO PARSE - not called outside of initcp
        && length $Cpanel::CONF{'file_upload_max_bytes'}    # PPI NO PARSE - not called outside of initcp
        && $Cpanel::CONF{'file_upload_max_bytes'} ne 'unlimited'
      ) {                                                   # PPI NO PARSE - not called outside of initcp
        $file_upload_max_bytes = int( $Cpanel::CONF{'file_upload_max_bytes'} ) * MB;
    }
    else {
        $file_upload_max_bytes = 99999999999999;
    }

    # determine $max_upload
    #------------------------------------------------------------------
    #treats q{} and 0, as well as undef, as unlimited per-time upload
    my $max_upload = $Cpanel::CONF{'file_upload_max_bytes'}    # PPI NO PARSE - not called outside of initcp
      ? $Cpanel::CONF{'file_upload_max_bytes'} * MB            # PPI NO PARSE - not called outside of initcp
      : undef;

    if ( defined $quota_remain ) {
        my $total_upload_remaining = $quota_remain - $file_upload_must_leave_bytes;
        $total_upload_remaining = $total_upload_remaining > 0 ? $total_upload_remaining : 0;

        if ( defined $max_upload ) {
            if ( $max_upload > $total_upload_remaining ) {
                $max_upload = $total_upload_remaining;
            }
        }
        else {
            $max_upload = $total_upload_remaining;
        }
    }

    if ( defined $diskfree && defined $max_upload && $diskfree < $max_upload ) {
        $max_upload = $diskfree;
    }

    #------------------------------------------------------------------

    %RES = (
        'file_upload_max_bytes'        => $file_upload_max_bytes,
        'file_upload_must_leave_bytes' => $file_upload_must_leave_bytes,
        'spaceremain'                  => $quota_remain,
        'spacelimit'                   => $quota_limit,
        'spaceused'                    => $quota_used,
        'filesremain'                  => $files_remain,
        'fileslimit'                   => $files_limit,
        'filesused'                    => $files_used,
        'file_upload_remain'           => $max_upload,
    );

    foreach my $res ( keys %RES ) {
        if ( !defined $RES{$res} ) {
            $RES{$res} = '∞';
            $RES{ $res . '_humansize' } = '∞';
            next();
        }

        $RES{$res} = Cpanel::Math::_floatNum( length $RES{$res} && $RES{$res} eq $QUOTA_NOT_ENABLED_STRING ? 0 : $RES{$res}, 2 ) unless $res =~ m{files};
        $RES{ $res . '_humansize' } = Cpanel::Math::_toHumanSize( $RES{$res} );
    }
    return \%RES;
}

sub _uploadspace {
    my $res_ref = getdiskinfo();
    return ( $res_ref->{'file_upload_remain'} / MB );
}

sub _getspaceused {
    return ( displayquota() )[0];
}

sub _getspacelimit {
    return ( displayquota() )[1];
}

sub _getspaceused_bytes {
    return ( displayquota(1) )[0];
}

sub _getspacelimit_bytes {
    return ( displayquota(1) )[1];
}

sub _getspaceremain {
    return ( displayquota() )[2];
}

sub _getfilesused {
    return ( displayquota() )[3];
}

sub _getfileslimit {
    return ( displayquota() )[4];
}

sub _getfilesremain {
    return ( displayquota() )[5];
}

sub _getquota_mtime {
    require Cpanel::QuotaMtime;
    return Cpanel::QuotaMtime::get_quota_mtime() || ( time() + 10000 );
}

sub _quota_ttl {
    return 900;
}

sub _quota_min_expire_time {
    return 300;    # PPI NO PARSE - not called outside of initcp

}

1;
