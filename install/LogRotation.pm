package Install::LogRotation;

# cpanel - install/LogRotation.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use File::Find              ();
use File::Path              ();
use Cpanel::Logd::Dynamic   ();
use Cpanel::FileUtils::Copy ();
use Cpanel::FileUtils::Move ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics

our $VERSION = '1.0';

our $LOG_ROTATION_DIR       = '/var/cpanel/log_rotation';
our $LOG_ROTATION_DIR_PERMS = 0711;

=head1 DESCRIPTION

    Create symlinks in /var/cpanel/log_rotation
    to different access logs.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('logrotation');
    $self->add_dependencies(qw(pre users));

    return $self;
}

sub _move_links {
    my $old_dir = shift;
    my $new_dir = shift;

    if ( opendir my $DIR, $old_dir ) {
        my @files = grep { /\.cpanellogd$/ } readdir $DIR;
        closedir $DIR;

        foreach my $file (@files) {
            my $from = "$old_dir/$file";
            my $to   = "$new_dir/$file";
            if ( !Cpanel::FileUtils::Move::safemv( $from, $to ) ) {
                warn "Failed to move $from to $to";
            }
        }
    }
}

# if they have the old name, we preserve the settings
# if they have settings in the new dir, we migrate them
sub _migrate_settings {
    my $old_dir = '/var/cpanel/cpanellogd.custom';
    my $new_dir = $LOG_ROTATION_DIR;

    if ( -d $old_dir && !-d $new_dir ) {
        mkdir $new_dir;

        chmod 0711, $new_dir;

        _move_links( $old_dir, $new_dir );

        if ( !File::Path::rmtree( $old_dir, { verbose => 1 } ) ) {
            warn "Failed to remove $old_dir";
        }
    }

    return 1;
}

sub _create_logd_link_entry {
    my ($log) = @_;
    my $name  = "cp_$log";
    my $path  = $log =~ tr{/}{} ? $log : "/usr/local/cpanel/logs/$log";
    if ( !Cpanel::Logd::Dynamic::create_logd_link_entry( $name, $path ) ) {
        warn "Failed to create log link to $path";
        return;
    }
    return 1;
}

sub _setup_cpanel_defaults {
    if ( !-e '/var/cpanel/log_rotation/lastsaved.cpanel_log_rotation.pl' ) {
        my @log_list = (
            'cpbackup_transport_history.log',
            'cphulkd.log',
            'cphulkd_errors.log',
            'error_log',
            'login_log',
            'cpwrapd_log',
            'stats_log',
            'access_log',
            'cpdavd_error_log',
            'cpdavd_session_log',
            'license_log',
            'panic_log',
            'tailwatchd_log',
            'build_locale_databases_log',
            'addbandwidth.log',
            'safeapacherestart_log',
            'queueprocd.log',
            'secpol_log',
            'api_tokens_log',
            '/var/cpanel/accounting.log',
            'spamd_error_log',
            'incoming_http_requests.log',
            'api_log',
        );

        foreach my $log (@log_list) {
            _create_logd_link_entry($log);
        }
    }

    # NOTE: Any time you add a new log file, bump this version and add a new if
    # stanza below.  Do not add new files to an existing stanza, as they will
    # not get added on existing systems.
    my $CURRENT_LOGROTATION_VERSION = 11;
    my $log_rotation_version        = _get_log_rotation_version();
    if ( $log_rotation_version < 3 ) {
        _create_logd_link_entry('safeapacherestart_log');
        _create_logd_link_entry('build_locale_databases_log');
        _create_logd_link_entry('addbandwidth.log');
    }
    if ( $log_rotation_version < 4 ) {
        _create_logd_link_entry('queueprocd.log');
    }
    if ( $log_rotation_version < 5 ) {
        _create_logd_link_entry('cpwrapd_log');
    }
    if ( $log_rotation_version < 6 ) {
        _create_logd_link_entry('cpdavd_session_log');
    }
    if ( $log_rotation_version < 7 ) {
        _create_logd_link_entry('splitlogs_log');
        _create_logd_link_entry('dnsadmin_log');
        _create_logd_link_entry('backup_restore_manager_error_log');
        _create_logd_link_entry('backup_restore_manager_log');
        _create_logd_link_entry('session_log');
        _create_logd_link_entry('secpol_log');
    }
    if ( $log_rotation_version < 8 ) {
        _create_logd_link_entry('api_tokens_log');
    }
    if ( $log_rotation_version < 9 ) {
        _create_logd_link_entry('/var/cpanel/accounting.log');
    }
    if ( $log_rotation_version < 10 ) {
        _create_logd_link_entry('spamd_error_log');
    }
    if ( $log_rotation_version < 11 ) {
        _create_logd_link_entry('api_log');
    }
    if ( $log_rotation_version != $CURRENT_LOGROTATION_VERSION ) {
        _update_log_rotation_version($CURRENT_LOGROTATION_VERSION);
    }

    return 1;
}

sub _setup_apache_defaults {
    if ( !-e '/var/cpanel/log_rotation/lastsaved.apache_log_rotation.pl' ) {
        my @log_list = (
            'suexec_log',
            'ssl_engine_log',
            'access_log',
            'error_log',
            'ssl_access_log',
            'ssl_error_log',
            'mod_jk.log',
            'modsec_debug.log',
            'referer_log',
            'agent_log',
            'ssl_log',
            'suphp_log',
            'ssl_data_log',
        );

        foreach my $log (@log_list) {
            my $name = 'cp__apache__' . $log;
            my $path = apache_paths_facade->dir_logs() . "/$log";
            if ( !Cpanel::Logd::Dynamic::create_logd_link_entry( $name, $path, 1 ) ) {    # force it so that targets will be updated
                warn "Failed to create log link to $path";
            }
        }
    }

    return 1;
}

sub _get_log_rotation_version {
    return 0 unless -e '/var/cpanel/version/log_rotation';
    open( my $fh, '<', '/var/cpanel/version/log_rotation' ) or do {
        warn "Failed to read log_rotation version.\n";
        return 0;
    };
    my $line = <$fh>;
    return $1 if $line =~ /^Version: (\d+)/;
    return 0;
}

sub _update_log_rotation_version {
    my $version = shift || 1;
    open( my $fh, '>', '/var/cpanel/version/log_rotation' ) or do {
        warn "Failed to mark log_rotation version.\n";
        return 0;
    };
    print $fh "Version: $version\n";
    return;
}

sub _setup_logrotate_conf {
    my $template_spec = '/usr/local/cpanel/etc/logrotate.d/*';
    my $target_dir    = '/etc/logrotate.d';
    foreach my $file ( glob $template_spec ) {
        if ( !Cpanel::FileUtils::Copy::safecopy( $file, $target_dir ) ) {
            warn "Failed to copy $file to $target_dir";
        }
    }
    return;
}

sub perform {
    my $self = shift;

    _migrate_settings();
    _setup_cpanel_defaults();
    _setup_apache_defaults();
    _setup_logrotate_conf();

    chmod $LOG_ROTATION_DIR_PERMS, $LOG_ROTATION_DIR;

    return 1;
}

1;

__END__
