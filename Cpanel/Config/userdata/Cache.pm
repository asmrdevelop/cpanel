package Cpanel::Config::userdata::Cache;

# cpanel - Cpanel/Config/userdata/Cache.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
#   Modules in this code fetch userdata information (/var/cpanel/userdata/$user/$domain)
#   that has been cached in /etc/userdatadomains.
#
#   These functions will not work if called by a non-root user, as the cache files
#   is only readable by root.
#

use strict;
use warnings;

use Cpanel::Debug                        ();
use Cpanel::Config::userdata::Constants  ();
use Cpanel::AdminBin::Serializer         ();    # PPI USE OK - for Cpanel::AdminBin::Serializer::FailOK
use Cpanel::AdminBin::Serializer::FailOK ();
use Cpanel::LoadFile::ReadFast           ();

use constant _ENOENT => 2;

our $CACHE_FILE         = '/etc/userdatadomains';
our $CACHE_FILE_POSTFIX = '.json';

our $FIELD_USER          = 0;
our $FIELD_OWNER         = 1;
our $FIELD_DOMAIN_TYPE   = 2;
our $FIELD_PARENT_DOMAIN = 3;
our $FIELD_DOCROOT       = 4;
our $FIELD_PHP_VERSION   = 9;

# Note: the field names are used as hash key names to map the array. Do not change the name of the fields
our @FIELD_NAMES = qw(user user_owner domain_type parent_domain docroot ip_port ssl_ip_port ipv6_dedicated modsecurity_disabled php_version);

my $memory_cache_user;
my $memory_cache;

my %userdata;

sub reset_cache {
    %userdata          = ();
    $memory_cache_user = undef;
}

sub get_user {
    return _get_info( @_, 0 );
}

sub get_owner {
    return _get_info( @_, 1 );
}

sub get_domain_type {
    return _get_info( @_, 2 );
}

sub get_parent_domain {
    return _get_info( @_, 3 );
}

sub get_docroot {
    return _get_info( @_, 4 );
}

# Returns a true value if mod_security is disabled for the domain (userdata flag: secruleengineoff)
sub get_modsecurity_disabled {
    return _get_info( @_, 8 );
}

sub _get_info {    ## no critic qw(Subroutines::RequireArgUnpacking)
    if ( @_ < 3 ) { goto &_get_info_as_root; }

    my ( $user, $domain, $fieldnum ) = @_;

    if ( !exists $userdata{$domain} ) {
        require Cpanel::FileLookup;
        $userdata{$domain} = Cpanel::FileLookup::filelookup( "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/cache", 'key' => $domain );
    }

    # Returns undef on non-existant domain
    # All callers currently check for this and expect
    return $userdata{$domain} ? ( split '==', $userdata{$domain}, -1 )[$fieldnum] : undef;
}

sub _get_info_as_root {
    Cpanel::Debug::log_die("Cannot read main userdata cache file as non-root user!")
      if ( $> != 0 );

    # Yes, we want to die() here; if this happens, it's a bug that needs to be found and fixed.
    # The solution is, either call with ($user, $domain) instead of just ($domain), or call as root.
    # Note that calling with ($user, $domain) is faster even when running as root, as the user cache file is smaller

    my ( $domain, $fieldnum ) = @_;

    if ( !exists $userdata{$domain} ) {
        require Cpanel::FileLookup;
        $userdata{$domain} = Cpanel::FileLookup::filelookup( $CACHE_FILE, 'key' => $domain );
    }

    # Returns undef on non-existant domain
    # All callers currently check for this and expect
    return $userdata{$domain} ? ( split '==', $userdata{$domain} . -1 )[$fieldnum] : undef;
}

sub open_cache {
    my $user = shift;
    my ($filename) = get_cache_file($user);

    if ( !$filename ) {

        # This can happen on a fresh install; don't raise a warning
        return;
    }

    # Try opening the user cache (without locking)
    open( my $cache_fh, '<', $filename ) or do {
        if ( $! == _ENOENT() ) {
            require Cpanel::Config::userdata::UpdateCache;
            Cpanel::Config::userdata::UpdateCache::update_all_users();

            open( my $cache_fh, '<', $filename );    ## no critic qw(RequireCheckedOpen)
        }
    };

    return $cache_fh if fileno $cache_fh;

    Cpanel::Debug::log_warn( "Failed to open " . ( $user ? "${user}'s" : "the main" ) . " userdata cache file for reading: $!" );

    return undef;
}

sub get_cache_file {
    my ($user) = @_;

    my $filename;

    # If we're running as root and no username was supplied, open the main cache file
    if ( $> == 0 && !$user ) {
        $filename = $CACHE_FILE;
    }
    else {
        # We need a username to be able to open the single-user cache; use the current EUID
        require Cpanel::PwCache;
        $user ||= Cpanel::PwCache::getusername();

        if ( $user eq 'nobody' ) {
            die "“nobody” cannot read its own userdata files!\n";
        }

        $filename = "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/cache";
    }

    if ( !-e $filename ) {

        # ENOENT can happen legitimately for a newly created account,
        # so don’t warn in that case.
        if ( $! != _ENOENT() ) {
            warn "stat($filename) as UID $>: $!";
        }

        return;
    }

    return ( $filename, ( stat(_) )[ 9, 4 ] );
}

#For main/root cache, this returns:
#   0. domain
#   1. domain owner
#   2. domain owner’s owning reseller
#   3. “main”, “sub”, “addon”, or “parked”
#   4. “base” domain. This means different things to different domain types:
#       - “sub”: “base” is the DNS zone
#       - “main”: this value is irrelevant
#       - “parked” and “addon”: Apache’s ServerName
#   5. document root
#   6. non-SSL $ip:$port
#   7. SSL $ip:$port
#   8. IPv6 $ip,$port (non-SSL??)
#   9. modsec disabled?
#   10. PHP version
#
sub read_cache {
    my ($cache_fh) = @_;
    my $line;
    while ( $line = <$cache_fh> ) {
        next if ( $line =~ /^\s*#/ );
        chomp $line;
        next unless ( $line =~ /^\s*(.+?)\s*:\s*(.*)/ );
        my @result = ( $1, split( '==', $2, -1 ) );
        return wantarray ? @result : \@result;
    }
    return;
}

sub close_cache {
    my $cache_fh = $_[0];
    if ($cache_fh) {
        unless ( $cache_fh->close() ) {
            Cpanel::Debug::log_warn("Error closing cache file: $!");
        }
    }
    return;
}

#Returns a hash of:
#   domain => [ user, userowner, type, maindomain, maindocroot, "ip:port", "sslip:port" ]
sub load_cache {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my ( $user, $PERMIT_MEMORY_CACHE ) = @_;
    if ( defined $user && $PERMIT_MEMORY_CACHE && defined $memory_cache_user && $memory_cache_user eq $user ) {
        return wantarray ? %$memory_cache : $memory_cache;
    }

    my $cache_ref;
    my ( $cache_file, $cache_file_mtime, $cache_file_uid ) = get_cache_file(@_);
    if ( !$cache_file ) {

        #  Failed to find the cache file.
        #  This can happen on a fresh install; don't raise a warning
        return;
    }

    my $cache_file_stor_mtime = ( stat( $cache_file . $CACHE_FILE_POSTFIX ) )[9];

    if ( !$cache_file_stor_mtime && ( $! != _ENOENT() ) ) {
        Cpanel::Debug::log_warn("stat($cache_file$CACHE_FILE_POSTFIX): $!");
    }

    if ($cache_file_stor_mtime) {
        my $use_cache_yn = ( $cache_file_stor_mtime >= $cache_file_mtime );
        $use_cache_yn &&= $cache_file_stor_mtime <= time();

        if ( open my $cache_stor_fh, '<', $cache_file . $CACHE_FILE_POSTFIX ) {
            $cache_ref = Cpanel::AdminBin::Serializer::FailOK::LoadFile($cache_stor_fh);
            if ($cache_ref) {
                if ($PERMIT_MEMORY_CACHE) {
                    $memory_cache      = $cache_ref;
                    $memory_cache_user = $user;
                }
                return wantarray ? %{$cache_ref} : $cache_ref;
            }
        }
        else {
            Cpanel::Debug::log_warn("open($cache_file$CACHE_FILE_POSTFIX): $!");
        }
    }

    if ( open( my $cache_fh, '<', $cache_file ) ) {

        #
        #   Scan the file; for each line that looks like a key/value pair,
        #   split the value using '==' as the delimiter,
        #   and map it to a hash entry
        #   (Non-matching lines are mapped to an empty list)
        #
        #   Note:
        #   according to NYTProf, "( <$cache> )" translates to a single call to readline
        #
        my $data = '';
        Cpanel::LoadFile::ReadFast::read_all_fast( $cache_fh, $data );

        $cache_ref = {
            map {
                $_ = [ split( /(?:\: |\n)/, $_, 3 ) ];
                (
                      ( $_->[0] && $_->[1] )
                    ? ( $_->[0] => [ split '==', $_->[1], -1 ] )
                    : ()
                )
            } split( m{\n}, $data )
        };

        close_cache($cache_fh);
    }
    else {
        Cpanel::Debug::log_warn( "Failed to open " . ( $user ? "${user}'s" : "the main" ) . " userdata cache file for reading: $!" );
        return;
    }

    if ($PERMIT_MEMORY_CACHE) {
        $memory_cache      = $cache_ref;
        $memory_cache_user = $user;
    }

    return wantarray ? %{$cache_ref} : $cache_ref;
}

1;
