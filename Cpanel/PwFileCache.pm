package Cpanel::PwFileCache;

# cpanel - Cpanel/PwFileCache.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic (RequireUseWarnings)

use Cpanel::Fcntl::Constants             ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Auth::Digest::Realm          ();
use Cpanel::PasswdStrength::Check        ();

our $VERSION = 1.6;
our $DEBUG   = 0;

sub load_pw_cache {    ## no critic (RequireArgUnpacking)
    my $now                     = $_[0]->{'now'}               || time();
    my $passwd_file_mtime       = $_[0]->{'passwd_file_mtime'} || 0;
    my $quota_file_mtime        = $_[0]->{'quota_file_mtime'}  || 0;
    my $passwd_cache_file       = $_[0]->{'passwd_cache_file'};
    my $passwd_cache_dir        = $_[0]->{'passwd_cache_dir'};
    my $passwd_cache_file_mtime = $_[0]->{'passwd_cache_file_mtime'};

    if (
        # cache name is not empty
        length $passwd_cache_file

        # cache name is not a path traversal
        && ( length($passwd_cache_file) > 2 || $passwd_cache_file =~ tr{.}{}c )

        # cache name is valid for a username or uid
        && $passwd_cache_file !~ tr{\x{00}-\x{20}\x{7f}:/#}{}

        # cache file exists
        && defined( $passwd_cache_file_mtime //= ( stat( $passwd_cache_dir . '/' . $passwd_cache_file ) )[9] )

        # cache file is newer than the passwd file
        && $passwd_cache_file_mtime > $passwd_file_mtime

        # cache file is newer than the quota file
        && $passwd_cache_file_mtime > $quota_file_mtime

        # cache file is not from the future
        && $passwd_cache_file_mtime <= $now

        # cache file could be opened for reading
        && open( my $pwcache_fh, '<', $passwd_cache_dir . '/' . $passwd_cache_file )
    ) {

        # We read this in one line because the data is small and we can avoid
        # multiple read calls which slows this down.
        local $/;
        my ( $data, $start, $mid, $end, %cache ) = ( scalar readline($pwcache_fh), 0 );
        close($pwcache_fh);
        while ( ( $mid = index( $data, ':', $start ) ) != -1 && ( $end = index( $data, "\n", $mid + 1 ) ) != -1 ) {

            # reject cache if it contains empty keys, or delimiters not allowed in password files
            goto CACHE_MISS if ( $mid == ( $start + 1 ) || 1 != ( substr( $data, $start, $end - $start ) =~ tr{:}{} ) );

            $cache{ substr( $data, $start, $mid - $start ) } = substr( $data, $mid + 1, $end - ( $mid + 1 ) );
            $start = $end + 1;
        }
        syswrite( STDERR, "[load_pw_cache] HIT [dir=$passwd_cache_dir] [file=$passwd_cache_file] [passwd_cache_file_mtime=$passwd_cache_file_mtime] [quota_file_mtime=$quota_file_mtime] [passwd_file_mtime=$passwd_file_mtime]\n" ) if $DEBUG;
        return \%cache;

    }
  CACHE_MISS:
    syswrite( STDERR, "[load_pw_cache] MISS [dir=$passwd_cache_dir] [file=$passwd_cache_file] [passwd_cache_file_mtime=$passwd_cache_file_mtime] [quota_file_mtime=$quota_file_mtime] [passwd_file_mtime=$passwd_file_mtime]\n" ) if $DEBUG;
    return {};
}

sub save_pw_cache {
    my $opref = shift;

    my $passwd_cache_file = $opref->{'passwd_cache_file'};
    my $passwd_cache_dir  = $opref->{'passwd_cache_dir'};
    my $uid               = $opref->{'uid'} || 0;
    my $gid               = $opref->{'gid'} || 0;
    my $keys              = $opref->{'keys'};

    # The cache file will always be a username or uid. Control characters, :, / and # are never valid.
    if (   !length $passwd_cache_file
        || ( length($passwd_cache_file) < 3 && $passwd_cache_file !~ tr{.}{}c )
        || $passwd_cache_file =~ tr{\x{00}-\x{20}\x{7f}:/#}{} ) {
        return;
    }

    require Digest::MD5;

    syswrite( STDERR, "[save_pw_cache] [dir=$passwd_cache_dir] [file=$passwd_cache_file]\n" ) if $DEBUG;
    my $reduce;

    if ( $uid != $> ) {
        $reduce = Cpanel::AccessIds::ReducedPrivileges->new( $uid, $gid );
    }

    if ( !-e $passwd_cache_dir ) {
        mkdir( $passwd_cache_dir, 0770 );
    }
    my $cache_fh;
    sysopen( $cache_fh, $passwd_cache_dir . '/' . $passwd_cache_file, $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_TRUNC | $Cpanel::Fcntl::Constants::O_CREAT, ( $reduce ? 0640 : 0600 ) );
    if ($cache_fh) {
        print {$cache_fh} 'passwd:' . $keys->{'encrypted_pass'} . "\n" if $keys->{'encrypted_pass'};
        print {$cache_fh} "quota:$keys->{'quota'}\n"                   if defined $keys->{'quota'};
        print {$cache_fh} "homedir:$keys->{'homedir'}\n"               if length $keys->{'homedir'};
        if ( $keys->{'digest-ha1'} || ( $opref->{'calculate-digest-ha1'} && $keys->{'pass'} ) ) {    # only save it if we have it
            my $realm = Cpanel::Auth::Digest::Realm::get_realm();
            print {$cache_fh} 'digest-ha1:' . ( $keys->{'digest-ha1'} || Digest::MD5::md5_hex( $passwd_cache_file . ':' . ( $keys->{'realm'} || $realm ) . ':' . $keys->{'pass'} ) ) . "\n";
        }
        print {$cache_fh} 'strength:' . Cpanel::PasswdStrength::Check::get_password_strength( $keys->{'pass'} ) . "\n" if $keys->{'pass'};
        print {$cache_fh} 'lastchanged:' . ( $keys->{'lastchanged'} || -1 ) . "\n";
        print {$cache_fh} 'perms:' . ( $keys->{'perms'} ) . "\n" if $keys->{'perms'};
        close($cache_fh);
    }

    undef $reduce;

    return;
}

sub clearcache {
    my ($opref)           = @_;
    my $passwd_cache_file = $opref->{'passwd_cache_file'};
    my $fname             = "$opref->{'passwd_cache_dir'}/$passwd_cache_file";

    # The cache file will always be a username or uid. Control characters, :, / and # are never valid.
    if (   !length $passwd_cache_file
        || ( length($passwd_cache_file) < 3 && $passwd_cache_file !~ tr{.}{}c )
        || $passwd_cache_file =~ tr{\x{00}-\x{20}\x{7f}:/#}{}
        || !-e $fname ) {
        return;
    }

    unlink($fname);
    return;
}

1;
