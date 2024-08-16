package Cpanel::Config::CpConfGuard::CORE;

# cpanel - Cpanel/Config/CpConfGuard/CORE.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::CpConfGuard::CORE - Internals for Cpanel::Config::CpConfGuard

=head1 SYNOPSIS

Not intended to be called directly. These are internals used by
Cpanel::Config::CpConfGuard

=cut

use Cpanel::ConfigFiles                  ();
use Cpanel::Debug                        ();
use Cpanel::FileUtils::Write::JSON::Lazy ();
use Cpanel::LoadModule                   ();
use Cpanel::Config::CpConfGuard          ();

our $SENDING_MISSING_FILE_NOTICE = 0;

my $FILESYS_PERMS = 0644;

sub find_missing_keys {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    # Setup our defaults object
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::CpConfGuard::Default');
    my $default = 'Cpanel::Config::CpConfGuard::Default'->new(
        current_config  => $self->{data},
        current_changes => $self->{changes},
    );

    # Deal with a missing cpanel.config
    if ( $self->{'is_missing'} ) {

        # try to use previous values from cache
        if ( UNIVERSAL::isa( $self->{'cache'}, 'HASH' ) && %{ $self->{'cache'} } ) {

            # will use default value from cache.
            # MUST be a copy to prevent mem cache corruption.
            $self->{'data'} = {};
            %{ $self->{'data'} } = %{ $self->{'cache'} };
            my $config = $self->{'data'};

            foreach my $key ( $default->get_keys() ) {
                next if exists $config->{$key};
                $config->{$key} = $default->get_default_for($key);
            }

        }
        else {
            # refresh all dynamic values ( do not use values from etc/cpanel.config )
            $self->{'data'} = $default->get_all_defaults();
        }

        $self->{'modified'} = 1;    # Mark as save needed.
        return;
    }

    # The file exists. Check for missing keys.
    # Prep variables for easier use later.
    my $cache = $self->{'cache'};
    undef( $self->{'cache'} );    # we do not need the cache after the first pass
    my $config = $self->{'data'};

    my $changes = $self->{'changes'};    # used for notifications

    # We shouldn't be validating if tweak_unset_vars is missing. Just make sure it's a string.
    # This is internal logic between Tweak Settings and CpConfGuard.
    $config->{'tweak_unset_vars'} ||= '';

    # Look for missing keys in the existing file.
    foreach my $key ( $default->get_keys() ) {
        next if exists $config->{$key};

        $self->{'modified'} = 1;    # Mark as save needed.

        # Fall back to cache file value if possible.
        if ( exists $cache->{$key} ) {
            $config->{$key} = $cache->{$key};

            $changes->{'from_cache'} ||= [];
            push @{ $changes->{'from_cache'} }, $key;

            $changes->{'changed_keys'} ||= {};
            $changes->{'changed_keys'}{$key} = 'from_cache';

            next;
        }

        # Not in cache.
        my $changes_type = $default->is_dynamic($key) ? 'from_dynamic' : 'from_default';

        $changes->{'changed_keys'} ||= {};
        $changes->{'changed_keys'}{$key} = $changes_type;

        $changes->{$changes_type} ||= [];
        push @{ $changes->{$changes_type} }, $key;

        # Get the dynamic value or the default.
        $config->{$key} = $default->get_default_for($key);
    }

    # check if some dead variables need to be removed
    foreach my $key ( @{ $default->dead_variables() } ) {
        next unless exists $config->{$key};

        $self->{'modified'} = 1;    # Mark as save needed.

        # Remove the key.
        delete( $config->{$key} );

        # Track what we did for notifications.
        $changes->{'dead_variable'} ||= [];
        push @{ $changes->{'dead_variable'} }, $key;

    }

    return;
}

sub validate_keys {
    my ($self) = @_;

    _verify_called_as_object_method($self);

    # manage cycle hours and more
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::CpConfGuard::Validate');
    my $invalid = 'Cpanel::Config::CpConfGuard::Validate'->can('patch_cfg')->( $self->{'data'} );
    if (%$invalid) {
        $self->{modified} = 1;
        $self->{'changes'}->{'invalid'} = $invalid;
    }

    return;
}

sub notify_and_save_if_changed {
    my ($self) = @_;
    _verify_called_as_object_method($self);

    return if !$self->{'use_lock'};
    return if !$self->{'modified'};

    my $config = $self->{'data'};

    if ( $ENV{'CPANEL_BASE_INSTALL'} ) {
        ;    # Do nothing for notification.
    }
    elsif ( $self->{'is_missing'} ) {
        $config->{'tweak_unset_vars'} = '';
        Cpanel::Debug::log_warn("Missing cpanel.config regenerating …");

        # send an email + log
        $self->notify_missing_file;
    }
    elsif ( %{ $self->{'changes'} } ) {
        my $changes = $self->{'changes'};

        my %uniq = map { $_ => 1 } @{ $changes->{'from_default'} || [] }, @{ $changes->{'from_dynamic'} || [] }, split( /\s*,\s*/, $config->{'tweak_unset_vars'} );
        $config->{'tweak_unset_vars'} = join ",", sort keys %uniq;

        # do not send any emails: just log a sumup message
        $self->log_missing_values();
    }

    return $self->save( keep_lock => 1 );
}

sub _server_locale {
    my ($self) = @_;

    _verify_called_as_object_method($self);

    # We're in a precarious load state so we can do no better than using the server_locale
    # This code should NEVER be done elsewhere where cpanel.config is otherwise readily available.
    # Also note, requiring Cpanel::Locale here will cause a circular dependency, which is why we don't use it up top.
    my $locale_name = $self->{'data'}->{'server_locale'} || 'en';
    require Cpanel::Locale;
    return Cpanel::Locale->_real_get_handle($locale_name);
}

# Longest string in an array.
sub _longest {
    my @array = @_;
    return length( ( sort { length $b <=> length $a } @array )[0] );
}

sub _stringify_undef {
    my $value = shift;
    return defined $value ? $value : '<undef>';
}

sub log_missing_values {
    my ($self) = @_;

    require Cpanel::Hostname;
    my $changes = $self->{'changes'};

    my $locale = $self->_server_locale();

    my $hostname = Cpanel::Hostname::gethostname();

    my $prev = $locale->set_context_plain();

    my $message = '';
    $message .= $locale->maketext( 'One or more key settings for “[_1]” were either not found in [asis,cPanel amp() WHM]’s server configuration file ([_2]), or were present but did not pass validation.', $hostname, $self->{'path'} ) . "\n";

    # Dynamic variables missing.
    if ( $changes->{'from_dynamic'} ) {
        $message .= $locale->maketext('The following settings were absent and have been selected based on the current state of your installation.');
        $message .= "\n";

        my @keys    = @{ $changes->{'from_dynamic'} };
        my $max_len = _longest(@keys) + 2;
        foreach my $key (@keys) {
            $message .= sprintf( "    %-${max_len}s= %s\n", $key, _stringify_undef( $self->{'data'}->{$key} ) );
        }
        $message .= "\n";
    }

    # Missing variables are still in the cache?
    if ( $changes->{'from_cache'} ) {
        $message .= $locale->maketext('The following settings were absent, but were restored from your [asis,cpanel.config.cache] file:');
        $message .= "\n";

        my @keys    = @{ $changes->{'from_cache'} };
        my $max_len = _longest(@keys) + 2;
        foreach my $key (@keys) {
            $message .= sprintf( "    %-${max_len}s= %s\n", $key, _stringify_undef( $self->{'data'}->{$key} ) );
        }
        $message .= "\n";
    }

    # Static defaults or invalid variables.
    if ( $changes->{'from_default'} or $changes->{'invalid'} ) {
        $message .= $locale->maketext('The following settings were absent or invalid. Your server has copied the defaults for them from the configuration defaults file ([asis,/usr/local/cpanel/etc/cpanel.config]).');
        $message .= "\n";

        if ( $changes->{'from_default'} ) {
            my @keys    = @{ $changes->{'from_default'} };
            my $max_len = _longest(@keys) + 2;
            foreach my $key (@keys) {
                $message .= sprintf( "    %-${max_len}s= %s\n", $key, _stringify_undef( $self->{'data'}->{$key} ) );
            }
        }

        if ( $changes->{'invalid'} ) {
            my $invalid = $changes->{'invalid'};
            my @keys    = keys %$invalid;
            my $max_len = _longest(@keys) + 2;
            foreach my $key (@keys) {
                $message .= sprintf( "    %-${max_len}s= %s (Previously set to '%s')\n", $key, _stringify_undef( $invalid->{$key}->{'to'} ), _stringify_undef( $invalid->{$key}->{'from'} ) );
            }
        }
        $message .= "\n";
    }

    # Dead variables.
    if ( $changes->{'dead_variable'} ) {
        $message .= $locale->maketext('The following settings are obsolete and have been removed from the server configuration file:');
        $message .= "\n";
        $message .= '    ' . join( ', ', @{ $changes->{'dead_variable'} } );
        $message .= "\n\n";
    }

    $message .= $locale->maketext( 'Read the [asis,cpanel.config] file [output,url,_1,documentation] for important information about this file.', 'https://go.cpanel.net/cpconfig' );
    $message .= "\n\n";

    Cpanel::Debug::logger();    # initialize the logger
    local $Cpanel::Logger::ENABLE_BACKTRACE = 0;
    foreach my $chunk ( split( /\n+/, $message ) ) {
        Cpanel::Debug::log_warn($chunk);
    }

    $locale->set_context($prev);

    return;
}

sub notify_missing_file {
    my ($self) = @_;

    if ($SENDING_MISSING_FILE_NOTICE) {
        return;    #Already sending notification, don't double up
    }

    require Cpanel::Hostname;
    local $SENDING_MISSING_FILE_NOTICE = 1;

    my $locale = $self->_server_locale();
    my $prev   = $locale->set_context_plain();

    my @to_log;
    my %critical_values;

    my $hostname = Cpanel::Hostname::gethostname();
    push @to_log, $locale->maketext('Your server has copied the defaults from your cache and the configuration defaults file ([asis,/usr/local/cpanel/etc/cpanel.config]) to [asis,/var/cpanel/cpanel.config], and it has generated the following critical values:');
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::CpConfGuard::Default');
    my $critical = Cpanel::Config::CpConfGuard::Default::critical_values();
    my $max_len  = _longest(@$critical) + 2;
    my $critical_value;
    foreach my $key ( sort @$critical ) {
        $critical_value = _stringify_undef( $self->{'data'}->{$key} );
        $critical_values{$key} = $critical_value;
        push @to_log, sprintf( "    %-${max_len}s= %s\n", $key, $critical_value );
    }

    push @to_log, $locale->maketext( 'Read the [asis,cpanel.config] file [output,url,_1,documentation] for more information about this file.', 'https://go.cpanel.net/cpconfig' ) . ' ';

    Cpanel::Debug::logger();    # initialize the logger
    local $Cpanel::Logger::ENABLE_BACKTRACE = 0;

    # we use a shorter version for the log file
    foreach my $chunk (@to_log) {
        chomp $chunk;
        Cpanel::Debug::log_warn($chunk);
    }

    _icontact( \%critical_values );

    $locale->set_context($prev);

    return;
}

sub _icontact {
    my $critical_values = shift;

    Cpanel::LoadModule::load_perl_module("Cpanel::iContact::Class::Config::CpConfGuard");
    Cpanel::LoadModule::load_perl_module('Cpanel::Notify');
    'Cpanel::Notify'->can('notification_class')->(
        'class'            => 'Config::CpConfGuard',
        'application'      => 'Config::CpConfGuard',
        'constructor_args' => [
            'origin'          => 'cpanel.config',
            'critical_values' => $critical_values,
        ]
    );

    return;
}

sub save {
    my ( $self, %opts ) = @_;

    _verify_called_as_object_method($self);

    return unless ( $self->{'use_lock'} );

    # Don't let the distro perl do saves.
    return if ( $] > 5.007 && $] < 5.014 );

    return 1 if $Cpanel::Config::CpConfGuard::memory_only;

    # make sure file is opened in rw mode
    if ( !$self->{'rw'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::SafeFile');
        $self->{'fh'} = 'Cpanel::SafeFile'->can('safereopen')->( $self->{'fh'}, '+>', $Cpanel::ConfigFiles::cpanel_config_file );
        return $self->abort('Cannot reopen file for rw') unless $self->{'fh'};
        $self->{'rw'} = 1;
    }

    return $self->abort('Locked in parent, cannot save') if $self->{'pid'} != $$;
    return $self->abort('hash reference required')       if !UNIVERSAL::isa( $self->{'data'}, 'HASH' );

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::FlushConfig');
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::SaveCpConf');

    # save cpanel.config
    'Cpanel::Config::FlushConfig'->can('flushConfig')->(
        $self->{'fh'},
        $self->{'data'},
        '=',
        'Cpanel::Config::SaveCpConf'->can('header_message')->(),
        {
            sort  => 1,
            perms => $FILESYS_PERMS,
        },
    );

    # NOTE: We can NEVER usefully update cache here since the config file isn't closed.

    # Update memory cache for later save. (COPY DON'T ASSIGN!!!)
    %{$Cpanel::Config::CpConfGuard::MEM_CACHE} = %{ $self->{'data'} };

    return 1 if $opts{keep_lock};

    $self->release_lock;

    return 1;
}

sub _update_cache {
    my ($self) = @_;

    _verify_called_as_object_method($self);

    # Don't update if we've already done so.
    return 0 if Cpanel::Config::CpConfGuard::_cache_is_valid() && $self->{'cache_is_valid'};    # Don't re-write the file if it looks correct.

    # Looks like save was called. Save updates $MEM_CACHE
    $Cpanel::Config::CpConfGuard::MEM_CACHE_CPANEL_CONFIG_MTIME = ( stat($Cpanel::ConfigFiles::cpanel_config_file) )[9] || 0;

    return unless $self->{'use_lock'};                                                          # never update the cache when not root

    # Use the mem cache which gets updated on save, not data which might have been corrupted along the way.

    #prevent potential action-at-a-distance
    local $@;

    #NOTE: write_file() can both return 0 *and* throw an exception.
    #They mean different things, so we respond differently to them.
    my $ok = eval { Cpanel::FileUtils::Write::JSON::Lazy::write_file( $Cpanel::ConfigFiles::cpanel_config_cache_file, $Cpanel::Config::CpConfGuard::MEM_CACHE, $FILESYS_PERMS ) || 0 };

    if ( !$ok ) {

        #This means there was an actual error in the attempt to save.
        if ( !defined $ok ) {
            Cpanel::Debug::log_warn("Cannot update cache file: $Cpanel::ConfigFiles::cpanel_config_cache_file $@");

            unlink $Cpanel::ConfigFiles::cpanel_config_cache_file;
            return -1;
        }

        #If we got here, then we just didn’t have the modules
        #loaded that we need to save JSON.
        return;
    }

    my $past = ( stat($Cpanel::ConfigFiles::cpanel_config_cache_file) )[9] - 1;

    return _adjust_timestamp_for( $Cpanel::ConfigFiles::cpanel_config_file => $past );
}

sub _adjust_timestamp_for {
    my ( $f, $time ) = @_;

    return unless defined $f && defined $time;

    # try utime first:
    return 1 if utime( $time, $time, $f );

    # then try system touch:
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($time);
    my $stamp = sprintf( "%04d%02d%02d%02d%02d.%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

    unless ( _touch( $f => $stamp ) ) {
        Cpanel::Debug::log_warn("Cannot update mtime on $f: $@");
        return;
    }

    return 1;
}

sub _touch {    # mainly created to easily mock that part during the tests
    my ( $f, $stamp ) = @_;
    return system( 'touch', '-t', $stamp, $f ) == 0 ? 1 : 0;
}

sub _verify_called_as_object_method {
    if ( ref( $_[0] ) ne "Cpanel::Config::CpConfGuard" ) {
        die '' . ( caller(0) )[3] . " was not called as an object method [" . ref( $_[0] ) . "]\n";
    }
    return;
}

sub abort {
    my ( $self, $msg ) = @_;

    _verify_called_as_object_method($self);

    if ( $self->{'pid'} != $$ ) {
        Cpanel::Debug::log_die('Locked in parent, cannot release lock');
        return;
    }

    $self->release_lock();

    Cpanel::Debug::log_die($msg) if $msg;

    # If they're aborting, they may have messed with the data hash
    #clearcache();

    return 1;
}

sub set {
    my ( $self, $k, $v ) = @_;

    _verify_called_as_object_method($self);

    return unless defined $k;

    my $config = $self->{'data'};

    $config->{$k} = $v;

    if ( $config->{'tweak_unset_vars'} && index( $config->{'tweak_unset_vars'}, $k ) > -1 ) {
        my %unset = map { ( $_ => 1 ) } split( /\s*,\s*/, $config->{'tweak_unset_vars'} );
        delete( $unset{$k} );
        $config->{'tweak_unset_vars'} = join( ',', sort keys %unset );
    }

    return 1;
}

1;
