package Cpanel::Config::userdata::UpdateCache;

# cpanel - Cpanel/Config/userdata/UpdateCache.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache                     ();
use Cpanel::Config::userdata::Constants ();
use Cpanel::Config::userdata::Load      ();
use Cpanel::Config::userdata::Cache     ();
use Cpanel::Mkdir                       ();
use Cpanel::IPv6::UserDataUtil::Key     ();
use Cpanel::Debug                       ();
use Cpanel::Transaction::File::Raw      ();
use Cpanel::AdminBin::Serializer        ();
use Cpanel::FileUtils::Write            ();

=encoding utf-8

=head1 NAME

Cpanel::Config::userdata::UpdateCache - Update the userdata (vhost) cache

=head1 SYNOPSIS

    use Cpanel::Config::userdata::UpdateCache;

    Cpanel::Config::userdata::UpdateCache::update_all_users() or die;

    Cpanel::Config::userdata::UpdateCache::update('user1','user2') or die;

    Cpanel::Config::userdata::UpdateCache::update('user1','user2', {'collect' => 1}) or die;

=cut

our $PRODUCT_CONF_DIR = '/var/cpanel';

my $NUM_FIELDS = 10;    # This needs to be updated if you add a new field to the cache data

my $gid;

=head2 update($user1, $user2, ..., { 'collect' => 1, 'force' => 1 })

Arguments are a list of usernames.  If no usernames are specified, an exception
is thrown. (cf. C<update_all_users()>) Each user that needs to be processed
will be passed to _process_user() in order to update each individual user's
userdata cache (/var/cpanel/userdata/$USER/cache).   If _process_user() updates
the data, the force flag, or the collect flag is passed, the user's cache data
will be updated in the main userdata cache file (/etc/userdatadomains).

The last argument may be a hashref with the following keys:

=over 2

=item force

=over 2

Force _process_user to rebuild of each individual user's userdata cache (/var/cpanel/userdata/$USER/cache) file.
The data returned from _process_user() will always be updated in the main userdata
cache file (/etc/userdatadomains) even if the system believes it does not need to be.

=back

=item collect

=over 2

The data returned from _process_user() will always be updated in the main userdata
cache file (/etc/userdatadomains) even if the system believes it does not need to be.

=back

=back

If no users are passed and either force or collect is set, the system
will do a full rebuild of the main userdata cache file (/etc/userdatadomains) which
will result in stale users (deleted but not removed) being removed

If users are passed, the system will always update the main userdata cache
file (/etc/userdatadomains) with any changes from _process_user

=cut

sub update {
    if ( !scalar @_ || ref $_[0] eq 'HASH' ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("update() requires at least one user to update");
    }
    goto \&_update;
}

=head2 update_all_users()

Update the userdata cache for all users.  The cache file for
each user is updated as well as the main cache file for all users.

The arguments for update_all_users are the same as update except no
users may be passed.

=cut

sub update_all_users {
    if ( $_[0] && ( !ref $_[0] || ref $_[0] ne 'HASH' ) ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("update_all_users() takes no arguments or a single hashref.");
    }
    goto \&_update;

}

sub _update {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $opt =
      ( scalar(@_) && ref $_[-1] eq 'HASH' )
      ? pop(@_)
      : {};
    my @users = @_;

    # If we explicitly named one or more users, we *know* they've changed: force an update
    my $force_users  = 0;
    my $full_rebuild = 0;

    # Eliminate duplicates
    if (@users) {
        my %users = ( map { $_ => undef } @users );
        if ( exists $users{''} ) {
            require Cpanel::Carp;
            die Cpanel::Carp::safe_longmess("An empty user was passed to _update()");
        }

        @users = keys %users;

        $force_users = 1;

        # If we specify users we must update their cache reguardless as the we could
        # have just done an operation in the same second and the cache will
        # appear valid even though its not
    }
    else {
        $full_rebuild = ( $opt->{'force'} || $opt->{'collect'} ) ? 1 : 0;
        opendir my $ud_dir, $Cpanel::Config::userdata::Constants::USERDATA_DIR
          or Cpanel::Debug::log_die("Failed to open userdata directory: $!");
        @users = grep { substr( $_, 0, 1 ) ne '.' && length $_ } readdir($ud_dir);
        closedir $ud_dir;
    }

    my $start_time = time();
    my $cache      = {};
    my @users_updated;
    my @users_in_cache;
    for my $user (@users) {
        if ( -e "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/main" ) {
            my $main_mtime = ( stat(_) )[9];
            my ( $updated, $user_cache ) = _process_user( $user, ( $opt->{'force'} || $force_users ), $main_mtime );
            if ( $updated || $opt->{'force'} || $opt->{'collect'} || $force_users ) {
                push @users_updated, $user;

                if ($user_cache) {
                    push @users_in_cache, $user;
                    @{$cache}{ keys %$user_cache } = values %$user_cache;
                }
            }
        }
        else {
            push @users_updated, $user;    # User not found; we are updating following an account deletion
        }
    }

    #   Re-create the /etc/ cachefile if we are --force, --collect or we have users to update
    if ( $opt->{'force'} || $opt->{'collect'} || @users_updated ) {
        _update_main_cache( \@users_updated, $cache, \@users_in_cache, $start_time, $full_rebuild );
    }
    return 1;
}

sub _process_user {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $user, $force_update, $main_mtime ) = @_;
    return 0 if $user eq 'nobody';

    my %mtime;
    my $cache_mtime;
    my $dir  = "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user";
    my $path = "$dir/cache";
    $mtime{'main'} = $main_mtime if $main_mtime;

    # If the cache doesn't exist, we *must* regenerate it completely
    if ( -e $path ) {
        $cache_mtime = ( stat _ )[9] || 0;
    }
    else {
        $force_update = 1;
        $cache_mtime  = 0;
    }

    if ( !$force_update ) {

        # See if anything has been updated since the cache was last generated
        my $needs_update = 0;
        if ( opendir( my $ud_dh, $dir ) ) {
            foreach my $file ( grep( !m/(?:^\.|cache(?:\.stor|\.json)?$)/, readdir($ud_dh) ) ) {
                if ( ( $mtime{$file} ||= ( stat "$dir/$file" )[9] || 0 ) >= $cache_mtime ) {
                    $needs_update = 1;
                    #
                    # keep going to collect the mtimes
                    #
                }
            }
            close $ud_dh;
        }
        return ( 0, undef ) unless $needs_update;

    }
    my %cache;
    my %unmatched;
    my %docroot;
    my %user;
    my %owner;
    my %ip;
    my %ip_ssl;
    my %ipv6;
    my %modsec_disabled;
    my %php_version;
    my $main_domain;
    my @parked_domains;
    my @sub_domains;
    my %addon_domains;

    my $start_time = time();
    my $trans      = Cpanel::Transaction::File::Raw->new( 'path' => $path, permissions => 0644 );

    my $original_text_ref = $trans->get_data();

    if ( !$force_update ) {
        %cache = map { ( split( ': ', $_ ) )[ 0, 1 ] } split( m{\n}, $$original_text_ref );
        delete @cache{ grep { !length $cache{$_} } keys %cache };
        %unmatched = map { $_ => undef } keys %cache;
    }

    # Read the userdata 'main' file
    my $ud_main = Cpanel::Config::userdata::Load::load_userdata_main($user);
    $main_domain    = $ud_main->{'main_domain'};
    @parked_domains = @{ $ud_main->{'parked_domains'} };
    @sub_domains    = @{ $ud_main->{'sub_domains'} };
    %addon_domains  = %{ $ud_main->{'addon_domains'} };
    $mtime{'main'} ||= ( stat "$dir/main" )[9] || 0;

    # Read the primary domain file, if it exists
    if ( $main_domain && ( $mtime{$main_domain} ||= ( stat "$dir/$main_domain" )[9] || 0 ) ) {
        delete $unmatched{$main_domain};
        if (   $force_update
            || !exists( $cache{$main_domain} )
            || $cache_mtime <= $mtime{$main_domain} ) {
            my $ud_primary = Cpanel::Config::userdata::Load::load_userdata( $user, $main_domain, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
            if ($ud_primary) {
                $user{$main_domain}            = $ud_primary->{'user'}  || $user;
                $owner{$main_domain}           = $ud_primary->{'owner'} || 'root';
                $docroot{$main_domain}         = $ud_primary->{'documentroot'};
                $ip{$main_domain}              = ( $ud_primary->{'ip'} || '' ) . ':' . ( $ud_primary->{'port'} || '80' );
                $modsec_disabled{$main_domain} = $ud_primary->{'secruleengineoff'} ? 1 : 0;
                $php_version{$main_domain}     = $ud_primary->{'phpversion'} || '';

                if ( ref $ud_primary->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key} eq 'HASH' ) {
                    foreach my $key ( keys %{ $ud_primary->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key} } ) {
                        my $dedicated =
                          ( ref $ud_primary->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key}{$key} eq 'HASH' )
                          ? $ud_primary->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key}{$key}{'dedicated'}
                          : 0;
                        $dedicated = $dedicated ? 1 : 0;
                        $ipv6{$main_domain} .= $key . ',' . $dedicated;
                    }
                }

                my $ud_ssl = Cpanel::Config::userdata::Load::user_has_ssl_domain( $user, $main_domain );
                $ud_ssl &&= Cpanel::Config::userdata::Load::load_ssl_domain_userdata( $user, $main_domain, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
                if ( $ud_ssl && $ud_ssl->{'ip'} ) {
                    $ip_ssl{$main_domain} = ( $ud_ssl->{'ip'} || '' ) . ':' . ( $ud_ssl->{'port'} || '443' );
                }
                else {
                    $ip_ssl{$main_domain} = '';
                }

                $cache{$main_domain} = _format_row( $user{$main_domain}, $owner{$main_domain}, 'main', $main_domain, $docroot{$main_domain} || '', $ip{$main_domain} || '', $ip_ssl{$main_domain} || '', $ipv6{$main_domain} || '', $modsec_disabled{$main_domain}, $php_version{$main_domain} );

            }
            else {
                _not_found( $user, $main_domain );
            }
        }

        # Read all the parked domains, which share a docroot with the primary domain
        for my $parked_domain (@parked_domains) {
            delete $unmatched{$parked_domain};
            if (   $force_update
                || !exists( $cache{$parked_domain} )
                || $cache_mtime <= $mtime{$main_domain} ) {
                $cache{$parked_domain} = _format_row( $user{$main_domain}, $owner{$main_domain}, 'parked', $main_domain, $docroot{$main_domain} || '', $ip{$main_domain} || '', $ip_ssl{$main_domain} || '', '', $modsec_disabled{$main_domain}, $php_version{$main_domain} );

            }
        }
    }
    else {
        _not_found( $user, $main_domain || 'UNKNOWN' );
    }

    # Read all the subdomains, and cache their documentroots
    for my $sub_domain (@sub_domains) {
        $mtime{$sub_domain} ||= ( stat "$dir/$sub_domain" )[9] || 0;
        if ( $mtime{$sub_domain} ) {
            delete $unmatched{$sub_domain};
            if (   $force_update
                || !exists( $cache{$sub_domain} )
                || $cache_mtime <= $mtime{$sub_domain} ) {
                my $ud_sub = Cpanel::Config::userdata::Load::load_userdata( $user, $sub_domain, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
                if ($ud_sub) {
                    ( my $parent_domain = $sub_domain ) =~ s{^.*?\.}{};
                    $user{$sub_domain}            = $ud_sub->{'user'}  || $user{$parent_domain}  || ( $main_domain && $user{$main_domain} )  || $user;
                    $owner{$sub_domain}           = $ud_sub->{'owner'} || $owner{$parent_domain} || ( $main_domain && $owner{$main_domain} ) || 'root';
                    $docroot{$sub_domain}         = $ud_sub->{'documentroot'};
                    $modsec_disabled{$sub_domain} = $ud_sub->{'secruleengineoff'} ? 1 : 0;
                    $php_version{$sub_domain}     = $ud_sub->{'phpversion'} || '';
                    $ip{$sub_domain}              = ( $ud_sub->{'ip'} || '' ) . ':' . ( $ud_sub->{'port'} || '80' );

                    my $ud_ssl = Cpanel::Config::userdata::Load::user_has_ssl_domain( $user, $sub_domain );
                    $ud_ssl &&= Cpanel::Config::userdata::Load::load_ssl_domain_userdata( $user, $sub_domain, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
                    if ( $ud_ssl && $ud_ssl->{'ip'} ) {
                        $ip_ssl{$sub_domain} = ( $ud_ssl->{'ip'} || '' ) . ':' . ( $ud_ssl->{'port'} || '443' );
                    }
                    else {
                        $ip_ssl{$sub_domain} = '';
                    }

                    $cache{$sub_domain} = _format_row(
                        $user{$sub_domain}, $owner{$sub_domain},  'sub', $main_domain || '',            $docroot{$sub_domain} || '',
                        $ip{$sub_domain},   $ip_ssl{$sub_domain}, '',    $modsec_disabled{$sub_domain}, $php_version{$sub_domain}
                    );

                }
                else {
                    _not_found( $user, $sub_domain );
                }
            }
        }
        else {
            _not_found( $user, $sub_domain );
        }
    }

    # Read all the addon domains, which share docroots with subdomains above
    for my $addon_domain ( keys %addon_domains ) {
        my $sub_domain = $addon_domains{$addon_domain};
        if ( $mtime{$sub_domain} ) {
            delete $unmatched{$addon_domain};
            if (   $force_update
                || !exists( $cache{$addon_domain} )
                || $cache_mtime <= $mtime{$sub_domain} ) {
                $cache{$addon_domain} = _format_row(
                    $user{$sub_domain}, $owner{$sub_domain},  'addon', $sub_domain,                   $docroot{$sub_domain},
                    $ip{$sub_domain},   $ip_ssl{$sub_domain}, '',      $modsec_disabled{$sub_domain}, $php_version{$sub_domain}
                );
            }
        }
    }

    # Delete any domain entries that failed to turn up
    delete @cache{ ( keys %unmatched ) };

    my $data_ref = \join( '', ( map { $_ . ": " . $cache{$_} . "\n" } sort keys %cache ) );

    my $data_has_changed        = ( $$data_ref ne $$original_text_ref ) ? 1 : 0;
    my $cache_file_with_postfix = $path . $Cpanel::Config::userdata::Cache::CACHE_FILE_POSTFIX;

    if ($data_has_changed) {
        $trans->set_data($data_ref);
    }
    else {
        my $cache_file_with_postfix_mtime = ( stat($cache_file_with_postfix) )[9];

        if ( $cache_file_with_postfix_mtime && $cache_file_with_postfix_mtime == $start_time && $trans->get_mtime() == $start_time ) {
            my ( $abort_ok, $abort_msg ) = $trans->abort();
            Cpanel::Debug::log_warn("Failed to abort user: $user cache update: $abort_msg") if !$abort_ok;
            return ( 0, undef );
        }
        elsif ($force_update) {
            return ( 0, \%cache );
        }
    }

    my $cache_file_temp = $path . '.build' . $Cpanel::Config::userdata::Cache::CACHE_FILE_POSTFIX;

    # the mtime must be set to the time right before we obtain the lock
    my %writable_cache = map { $_ => [ split( '==', $cache{$_}, -1 ) ] } keys %cache;    # -1 prevents dropping the last element if its undef
    Cpanel::FileUtils::Write::overwrite( $cache_file_temp, Cpanel::AdminBin::Serializer::Dump( \%writable_cache ), 0644 );
    utime $start_time, $start_time, $cache_file_temp;
    rename( $cache_file_temp, $cache_file_with_postfix ) or do {
        Cpanel::Debug::log_warn("rename($cache_file_temp, $cache_file_with_postfix): $!");
    };

    $trans->save_and_close_or_die( 'mtime' => $start_time );
    return ( 1, \%cache );
}

sub _not_found {
    my ( $user, $domain ) = @_;
    return Cpanel::Debug::log_info("Virtual host configuration not found for user $user, domain $domain");
}

sub _update_main_cache {
    my ( $users_ref, $cache_ref, $users_in_cache, $start_time, $full_rebuild ) = @_;

    die "_update_main_cache requires the time that the system started to examine the files" if !$start_time;
    die "_update_main_cache requires a list of users"                                       if !@{$users_ref};

    # Determine if the main cache needs to be updated (unless an update is being forced)
    my $main_cache = $Cpanel::Config::userdata::Cache::CACHE_FILE;

    #
    #   Open & lock the output file before we read the current contents of the cache,
    #   to avoid a race condition
    #
    _init_gid() unless defined $gid;

    my $cache_trans = Cpanel::Transaction::File::Raw->new( 'path' => $main_cache, 'permissions' => 0640, 'ownership' => [ 0, $gid ] );

    my %mtimes;

    # Populate the %mtimes hash, and select users
    # whose the cache file exists (i.e., has an mtime)
    my %users_with_cache_file    = map { $_ => 1 } grep { ( $mtimes{$_} = ( stat "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$_/cache" )[9] ) } @{$users_ref};
    my %users_missing_cache_file = map { $_ => 1 } grep { !$users_with_cache_file{$_} } @{$users_ref};

    my $cache = {};

    # If we are not doing a full rebuild we need to load the existing
    # data. If we are doing a full rebuild we should not load the existing
    # data as it may have stale entries that we want to remove
    if ( !$full_rebuild ) {
        $cache = Cpanel::Config::userdata::Cache::load_cache() || {};
        #
        # Much faster to delete all the keys we do not need
        # at once
        #
        my %users_to_update = map { $_ => 1 } @{$users_ref};
        delete @{$cache}{ grep { $users_to_update{ $cache->{$_}->[0] } } keys %$cache };
    }

    # First try to populate the cache
    # with the data passed in
    if ($cache_ref) {    # no need to load them if they are already provided
        $cache->{$_} = [ split( '==', $cache_ref->{$_}, -1 ) ] foreach keys %$cache_ref;    #-1 keeps the trailing empty field
        delete @users_with_cache_file{ @{$users_in_cache} };                                # no need to load the cache for users we already have
    }

    # If there are still users we have cache files
    # for that were not passed in cache_ref we need to load
    # them from disk
    for my $user ( keys %users_with_cache_file ) {
        local $@;
        my $user_cache = eval { Cpanel::Config::userdata::Cache::load_cache($user); };
        if ($@) {

            # Do not let one broken cache cause the entire
            # cache update to fail
            warn;
            next;
        }
        @{$cache}{ keys %$user_cache } = values %$user_cache;
    }

    if ( scalar keys %users_missing_cache_file ) {
        my $current_time = time();
        my $ensured_dir  = 0;
        foreach my $user ( keys %users_missing_cache_file ) {
            if ( !length $user || $user =~ tr{ \r\n\0}{} ) {
                Cpanel::Debug::log_warn("Internal Error: Invalid user “$user” passed to _update_main_cache()");
            }
            elsif ( -e "$PRODUCT_CONF_DIR/userdata/$user" && !-e "$PRODUCT_CONF_DIR/userdata/$user/main" ) {
                if ( !$ensured_dir ) {
                    Cpanel::Mkdir::ensure_directory_existence_and_mode( "$PRODUCT_CONF_DIR/userdata.orphaned", 0700 );
                    $ensured_dir = 1;
                }
                rename( "$PRODUCT_CONF_DIR/userdata/$user", "$PRODUCT_CONF_DIR/userdata.orphaned/$user.$current_time" );
                Cpanel::Debug::log_warn("Invalid user “$user” found in userdata, moved to $PRODUCT_CONF_DIR/userdata.orphaned/$user.$current_time");
            }
        }
    }

    # Write the data to a staging file, then rename to the real filename
    # so that we don't wind up with a partial cache file halfway through
    #
    # The data is expected to be unsorted as we generally read it all
    # in at once.
    $cache_trans->set_data(
        \join(
            '',
            map { $_ . ': ' . join( '==', @{ $cache->{$_} } ) . "\n" }
              keys %$cache
        )
    );

    # the mtime must be set to the time right before we obtaine the lock
    my %save_args = ( 'mtime' => $start_time );
    Cpanel::FileUtils::Write::overwrite( $main_cache . $Cpanel::Config::userdata::Cache::CACHE_FILE_POSTFIX . '.build', Cpanel::AdminBin::Serializer::Dump($cache), 0640 );
    utime( $save_args{'mtime'}, $save_args{'mtime'}, $main_cache . $Cpanel::Config::userdata::Cache::CACHE_FILE_POSTFIX . '.build' );
    rename( $main_cache . $Cpanel::Config::userdata::Cache::CACHE_FILE_POSTFIX . '.build', $main_cache . $Cpanel::Config::userdata::Cache::CACHE_FILE_POSTFIX );

    $cache_trans->save_or_die(%save_args);

    return 1;
}

sub _init_gid {
    if ( !defined $gid ) {
        $gid = ( Cpanel::PwCache::getpwnam_noshadow('mail') )[3];
        $gid = ( Cpanel::PwCache::getpwnam_noshadow('mailnull') )[3] if ( !defined $gid );
        $gid = 0                                                     if ( !defined $gid );
    }
    return $gid;
}

sub _format_row {
    my @fields = @_;
    @fields == $NUM_FIELDS or die "Incorrect number of fields; expected $NUM_FIELDS, but got " . @fields;
    return join '==', @fields;
}

sub match_format {

    #letitride.koston.org: koston==root==sub==koston.org==/home/koston/public_html/letitride==198.19.24.222:80==198.19.24.222:443==10:10:10:10:10:10==0==ea-php70

    return $_[0] =~ m{^[\*a-z0-9\-\.]+                        # Domain name
                      :\s+  \w+                             # User
                      ==    \w+                             # Reseller
                      ==    (?:main|sub|parked|addon)       # Type
                      ==    [a-z0-9\-\.]+                   # Base domain
                      ==    \/[^=]+                         # Document root
                      ==    \d+\.\d+\.\d+\.\d+:\d+          # IP addr/port
                      ==    (?:\d+\.\d+\.\d+\.\d+:\d+)?     # IP addr/port (SSL)
                      ==    [^=]*     # IPv6 Address
                      ==    [01]     # Mod Sec Enabled
                      ==    [^=]*     # php version
                      \n?$
                    }ix;
}

sub reset_cache {
    $gid = undef;
}

sub default_product_dir {
    $PRODUCT_CONF_DIR = shift if @_;
    return $PRODUCT_CONF_DIR;
}

1;
