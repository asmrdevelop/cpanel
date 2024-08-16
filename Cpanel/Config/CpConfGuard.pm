package Cpanel::Config::CpConfGuard;

# cpanel - Cpanel/Config/CpConfGuard.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::JSON::FailOK ();
use Cpanel::ConfigFiles  ();

use Cpanel::Debug    ();
use Cpanel::Destruct ();

use constant {
    _ENOENT => 2,
};

our $IN_LOAD                     = 0;
our $SENDING_MISSING_FILE_NOTICE = 0;

my $FILESYS_PERMS = 0644;

my $is_daemon;

BEGIN {
    $is_daemon = 0;    # initialize the value in the begin block
    if (   index( $0, 'updatenow' ) > -1
        || index( $0, 'cpsrvd' ) > -1
        || index( $0, 'cpdavd' ) > -1
        || index( $0, 'queueprocd' ) > -1
        || index( $0, 'tailwatchd' ) > -1
        || index( $0, 'cpanellogd' ) > -1
        || ( length $0 > 7 && substr( $0, -7 ) eq '.static' ) ) {
        $is_daemon = 1;
    }
}

my $module_file;

our ( $MEM_CACHE_CPANEL_CONFIG_MTIME, $MEM_CACHE ) = ( 0, undef );

#This mocks the parsed and validated values.
#It is largely indistinguishable from mocking this module entirely.
#If you want to mock cpanel.config itself, look in t/lib.
our $memory_only;

sub _is_daemon { $is_daemon };    # for testing

sub clearcache {
    $MEM_CACHE_CPANEL_CONFIG_MTIME = 0;
    $MEM_CACHE                     = undef;
    return;
}

#Possible %opts are:
#   loadcpconf  - boolean, sets read-only mode
#   no_validate - Disable validation.  This is only needed when we are making changes to the configuration (such as tweak settings) to avoid a duplicate validation
#
sub new {
    my ( $class, %opts ) = @_;

    Cpanel::JSON::FailOK::LoadJSONModule() if !$is_daemon && !$INC{'Cpanel/JSON.pm'};

    my $self = bless {
        %opts,    # to be improved
        'path'     => $Cpanel::ConfigFiles::cpanel_config_file,
        'pid'      => $$,
        'modified' => 0,
        'changes'  => {},
    }, $class;

    $self->{'use_lock'} //= ( $> == 0 ) ? 1 : 0;

    if ($memory_only) {
        $self->{'data'} = ref($memory_only) eq 'HASH' ? $memory_only : {};
        return $self;
    }

    # read the cache if not passed in.
    # this could be a method
    ( $self->{'cache'}, $self->{'cache_is_valid'} ) = get_cache();

    # we do not need a guard, just a read access to the data
    return $self if $self->{'loadcpconf'} && $self->{'cache_is_valid'};

    # open the cpconf file ( with lock if root )
    $self->load_cpconf_file();

    # Disallow validation of cpanel.config in daemons or static files are dangerous
    # With static files, there's a risk updatenow won't complete
    # in which case you'll be left on an old version with a new cpanel.config
    # With daemons, you're at risk that the daemon won't yet have the new settings during an upgrade.
    return $self if $is_daemon || $opts{'no_validate'} || !$self->{'use_lock'};

    $self->find_missing_keys();
    $self->validate_keys();
    $self->notify_and_save_if_changed();

    return $self;
}

sub set {
    require Cpanel::Config::CpConfGuard::CORE;
    goto \&Cpanel::Config::CpConfGuard::CORE::set;
}

sub config_copy {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    my $config = $self->{'data'} || $self->{'cache'} || {};
    return {%$config};
}

sub find_missing_keys {
    require Cpanel::Config::CpConfGuard::CORE;
    goto \&Cpanel::Config::CpConfGuard::CORE::find_missing_keys;
}

sub validate_keys {
    require Cpanel::Config::CpConfGuard::CORE;
    goto \&Cpanel::Config::CpConfGuard::CORE::validate_keys;
}

sub notify_and_save_if_changed {
    require Cpanel::Config::CpConfGuard::CORE;
    goto \&Cpanel::Config::CpConfGuard::CORE::notify_and_save_if_changed;
}

sub log_missing_values {
    require Cpanel::Config::CpConfGuard::CORE;
    goto \&Cpanel::Config::CpConfGuard::CORE::log_missing_values;
}

sub notify_missing_file {
    require Cpanel::Config::CpConfGuard::CORE;
    goto \&Cpanel::Config::CpConfGuard::CORE::notify_missing_file;
}

sub save {
    require Cpanel::Config::CpConfGuard::CORE;
    goto \&Cpanel::Config::CpConfGuard::CORE::save;
}

sub release_lock {
    my ($self) = @_;

    _verify_called_as_object_method($self);

    return unless $self->{'use_lock'} && defined $self->{'pid'} && $self->{'pid'} eq $$ && $self->{'lock'};

    # update the cache inbetween closing the file and releasing the lock file.
    require Cpanel::SafeFile;
    Cpanel::SafeFile::safeclose( $self->{'fh'}, $self->{'lock'}, sub { return $self->_update_cache() } );

    $self->{'fh'}        = $self->{'lock'} = undef;
    $self->{'is_locked'} = 0;

    return;
}

sub abort {
    require Cpanel::Config::CpConfGuard::CORE;
    goto \&Cpanel::Config::CpConfGuard::CORE::abort;
}

sub _update_cache {
    require Cpanel::Config::CpConfGuard::CORE;
    goto \&Cpanel::Config::CpConfGuard::CORE::_update_cache;
}

sub _server_locale {
    require Cpanel::Config::CpConfGuard::CORE;
    goto \&Cpanel::Config::CpConfGuard::CORE::_server_locale;
}

sub get_cache {

    my $cpanel_config_mtime = ( stat($Cpanel::ConfigFiles::cpanel_config_file) )[9] || 0;

    my $verbose = ( defined $Cpanel::Debug::level ? $Cpanel::Debug::level : 0 ) >= 5;

    # It's already loaded. return the memory cache
    if ( $MEM_CACHE && ref($MEM_CACHE) eq 'HASH' && $cpanel_config_mtime && $cpanel_config_mtime == $MEM_CACHE_CPANEL_CONFIG_MTIME ) {
        Cpanel::Debug::log_info("loadcpconf memory cache hit") if $verbose;

        return ( $MEM_CACHE, 1 );
    }

    clearcache();    # Invalidate the memory cache.

    Cpanel::Debug::log_info("loadcpconf memory cache miss") if $verbose;

    my $mtime_before_read;

    if ( !$INC{'Cpanel/JSON.pm'} ) {
        Cpanel::Debug::log_info("Cpanel::JSON not loaded. Skipping cache load.") if $verbose;
        return ( undef, 0 );
    }
    elsif ( -e $Cpanel::ConfigFiles::cpanel_config_cache_file ) {    # No need to do -r (costs 5 additional syscalls) since we write this 0644
        $mtime_before_read = ( stat _ )[9] || 0;
    }
    else {
        Cpanel::Debug::log_info("The cache file “$Cpanel::ConfigFiles::cpanel_config_cache_file” could not be read. Skipping cache load.") if $verbose;
        return ( undef, 0 );
    }

    my ( $mtime_after_read, $cpconf_ref ) = (0);

    # Loop until the file doesn't change out from under us.
    my $loop_count = 0;
    while ( $mtime_after_read != $mtime_before_read && $loop_count++ < 10 ) {
        sleep 1 if ( $mtime_after_read == time );    # If it was just written to, give it a second in case it's being written to.

        Cpanel::Debug::log_info( "loadcpconf cache_filesys_mtime = $mtime_before_read , filesys_mtime: $cpanel_config_mtime , memory_mtime: $MEM_CACHE_CPANEL_CONFIG_MTIME , now: " . time ) if $verbose;

        $cpconf_ref       = Cpanel::JSON::FailOK::LoadFile($Cpanel::ConfigFiles::cpanel_config_cache_file);
        $mtime_after_read = ( stat($Cpanel::ConfigFiles::cpanel_config_cache_file) )[9] || 0;

        # Only delay if the file appears to have changed.
        sleep 1 if ( $mtime_after_read != $mtime_before_read );
    }

    # Save to memory cache.
    if ( $cpconf_ref && scalar keys %{$cpconf_ref} ) {
        if ( _cache_is_valid( $cpanel_config_mtime, $mtime_after_read ) ) {
            Cpanel::Debug::log_info("loadcpconf file system cache hit") if $verbose;

            # Only store the cache in memory if we think it's valid.
            ( $MEM_CACHE, $MEM_CACHE_CPANEL_CONFIG_MTIME ) = ( $cpconf_ref, $cpanel_config_mtime );
            return ( $cpconf_ref, 1 );
        }
        Cpanel::Debug::log_info("loadcpconf cpanel.config.cache miss.") if $verbose;
        return ( $cpconf_ref, 0 );
    }

    Cpanel::Debug::log_info("loadcpconf cpanel.config.cache miss.") if $verbose;
    return ( undef, 0 );
}

sub _cache_is_valid {
    my ( $config_mtime, $cache_mtime ) = @_;

    $cache_mtime ||= ( stat($Cpanel::ConfigFiles::cpanel_config_cache_file) )[9] || 0;
    return 0 unless $cache_mtime;

    $config_mtime ||= ( stat($Cpanel::ConfigFiles::cpanel_config_file) )[9] || 0;
    return 0 unless $config_mtime;

    return ( $config_mtime + 1 == $cache_mtime ) ? 1 : 0;
}

sub load_cpconf_file {
    my ($self) = @_;

    if ($IN_LOAD) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("Load loop detected");
    }

    local $IN_LOAD = 1;

    _verify_called_as_object_method($self);

    # Load current config file.
    my $config = {};

    my $config_file = $Cpanel::ConfigFiles::cpanel_config_file;

    $self->{'is_missing'} = ( -e $config_file ) ? 0 : 1;

    return if ( !$self->{'use_lock'} && $self->{'is_missing'} );    # We can't do anything if the file is missing and we're not root. ABORT!

    # Touch the file and set it's ownership but leave it empty.
    if ( $self->{'use_lock'} && $self->{'is_missing'} ) {
        if ( open( my $touch_fh, '>>', $config_file ) ) {
            print {$touch_fh} '';
            close $touch_fh;
            chown 0, 0, $config_file;    # avoid pulling in Cpanel::PwCache for memory reasons
            chmod 0644, $config_file;
        }
    }

    # Try opening the file
    $self->{'rw'} = 0;
    $self->{'rw'} = 1 if ( $self->{'use_lock'} && !$self->{'cache_is_valid'} );

    # Load cpanel.config for RW only if the cache is invalid.
    require Cpanel::Config::LoadConfig;
    my ( $ref, $fh, $conflock, $err ) = Cpanel::Config::LoadConfig::loadConfig(
        $Cpanel::ConfigFiles::cpanel_config_file,
        $config,

        #if we must pass flags, then at least name them...
        (undef) x 4,
        {
            #don’t try to lock if we’re not root
            'keep_locked_open'   => !!$self->{'use_lock'},
            'nocache'            => 1,
            'rw'                 => $self->{'rw'},
            'allow_undef_values' => 1,
        },
    );

    if ( !$ref && !$fh && $! != _ENOENT() ) {
        $err ||= '(unknown error)';
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("Can’t read “$Cpanel::ConfigFiles::cpanel_config_file” ($err)");
    }

    $self->{'fh'}   = $fh;
    $self->{'lock'} = $conflock;
    $self->{'data'} = $config;

    if ( $self->{'use_lock'} ) {
        Cpanel::Debug::log_warn("Failed to establish lock on $Cpanel::ConfigFiles::cpanel_config_file") unless $self->{'lock'};

        Cpanel::Debug::log_warn("Failed to get file handle for $Cpanel::ConfigFiles::cpanel_config_file") unless $self->{'fh'};
    }

    $self->{'is_locked'} = defined $self->{'lock'} ? 1 : 0;    # alias for external usage

    # If get_cache failed, Copy into $MEM_CACHE so it'll go to the  Cpanel::JSON file.
    if ( !$MEM_CACHE ) {
        $MEM_CACHE  = {};
        %$MEM_CACHE = %$config;
    }

    return;
}

sub _verify_called_as_object_method {
    if ( ref( $_[0] ) ne __PACKAGE__ ) {
        die '' . ( caller(0) )[3] . " was not called as an object method [" . ref( $_[0] ) . "]\n";
    }
    return;
}

sub DESTROY {    ## no critic(RequireArgUnpacking)
    return 1 if ( $>     || $memory_only );        # Special modes we don't or won't write to cpanel.config files.
    return 2 if ( !$_[0] || !keys %{ $_[0] } );    # Nothing to cleanup if we're just a blessed empty hash.

    return if !$_[0]->{'lock'};

    # Only unsafe to unlock in_dangerous_global_destruction
    return if Cpanel::Destruct::in_dangerous_global_destruction();

    $_[0]->release_lock();                         # Close the file so we can update the cache properly.
    return;
}

1;
