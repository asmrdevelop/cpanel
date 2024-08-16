package Install::ChkServDSetup;

# cpanel - install/ChkServDSetup.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;
use Cpanel::Kill                 ();
use Cpanel::LoadFile             ();
use Cpanel::SafeRun::Simple      ();
use Cpanel::ServerTasks          ();
use Cpanel::FileUtils::Write     ();
use Cpanel::FileUtils::Link      ();
use Cpanel::FileUtils::Copy      ();
use Cpanel::FileUtils::Lines     ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::Services             ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Install and setup chkservd service
    to monitor services.

=over 1

=item Type: Fresh Install, Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('chkservdsetup');
    $self->add_dependencies(qw( taskqueue ));

    return $self;
}

sub _remove_old_service {
    my $name = shift;

    my $dir      = "/etc/chkserv.d/$name";
    my $stfile   = "/var/run/chkservd/$name";
    my $disabler = "/etc/${name}disable";

    my $need_restart = 0;

    foreach my $file ( $dir, $stfile, $disabler ) {
        if ( -e $file ) {
            Cpanel::FileUtils::Link::safeunlink($file) or warn "Failed to remove $file";
            print "$name has been removed\n";
            $need_restart = 1;
        }
    }
    return $need_restart;
}

sub _are_different {
    my $file1 = shift;
    my $file2 = shift;

    return Cpanel::LoadFile::loadfile($file1) ne Cpanel::LoadFile::loadfile($file2);
}

sub _update_service {
    my $cpname = shift;
    my $name   = shift || $cpname;

    my $dir      = '/etc/chkserv.d';
    my $file     = "$dir/$cpname";
    my $distfile = "/usr/local/cpanel/src/chkservd/chkserv.d/$name";
    my $disabler = "/etc/${name}disable";

    if ( -e $file ) {

        if ( -e $disabler
            && !Cpanel::FileUtils::TouchFile::touchfile($disabler) ) {
            warn "Failed to touch $disabler";
        }
        if ( _are_different( $distfile, $file ) ) {
            if ( !Cpanel::FileUtils::Link::safeunlink($file) ) {
                warn "Failed to unlink $file";
            }

            if ( !Cpanel::FileUtils::Copy::safecopy( $distfile, $dir ) ) {
                warn "Failed to copy $distfile into $dir";
            }
            print "$cpname has been updated\n";
            return 1;
        }
    }

    return;
}

sub _update_queueprocd {
    return if -e '/etc/chkserv.d/queueprocd';
    my $source = '/usr/local/cpanel/src/chkservd/chkserv.d/queueprocd';
    my $dir    = '/etc/chkserv.d';
    if ( !Cpanel::FileUtils::Copy::safecopy( $source, $dir ) ) {
        warn "Failed to copy $source into dir";
    }
    return 1;
}

sub _killall_and_remove {
    my $name = shift;
    my $file = "/etc/chkserv.d/$name";

    if ( -e $file ) {
        Cpanel::Kill::killall( 'KILL', $name, $Cpanel::Kill::VERBOSE );
        if ( !Cpanel::FileUtils::Link::safeunlink($file) ) {
            warn "Failed to remove $file";
        }

        return 1;
    }

    return;
}

sub _restart_daemon {
    local $@;
    eval { Cpanel::ServerTasks::queue_task( ['TailwatchTasks'], 'reloadtailwatch' ); };
    if ($@) {
        warn;
        return 0;
    }
    return 1;
}

sub _dnsonly_remove_old_files {
    my $restart_daemon;
    my @files_to_remove = (
        '/etc/chkserv.d/apache',
        '/etc/chkserv.d/cpanel_php_fpm',
        '/etc/chkserv.d/cpdavd',
        '/etc/chkserv.d/cpgreylistd',
        '/etc/chkserv.d/interchange',
        '/etc/chkserv.d/mailman',
        '/etc/chkserv.d/proftpd',
        '/etc/chkserv.d/spamd',
    );

    foreach my $file (@files_to_remove) {
        if ( -e $file ) {
            $restart_daemon = 1;
        }
        if ( !Cpanel::FileUtils::Link::safeunlink($file) ) {
            warn "Failed to remove $file";
        }
    }

    return $restart_daemon;
}

sub _dnsonly_touch_files {
    my $result         = 1;
    my @files_to_touch = (
        '/etc/apachedisable',
        '/etc/proftpddisable',
        '/etc/ftpddisable',
        '/etc/spamddisable',
        '/etc/eximstatsdisable',
    );

    foreach my $file (@files_to_touch) {
        if ( !Cpanel::FileUtils::TouchFile::touchfile($file) ) {
            warn "Failed to touch $file";
            $result = undef;
        }
    }

    if ($result) {
        return 1;
    }

    return;
}

sub _write_simple_chkservd_driver {
    my ($service) = @_;

    my $dist = "/usr/local/cpanel/src/chkservd/chkserv.d/$service";
    my $dir  = "/etc/chkserv.d";
    if ( !Cpanel::FileUtils::Copy::safecopy( $dist, $dir ) ) {
        warn "Failed to copy $dist to $dir";
    }

    my $chkservd_conf = '/etc/chkserv.d/chkservd.conf';
    my $fh;
    if ( !open $fh, '<', $chkservd_conf ) {
        Cpanel::FileUtils::Write::overwrite_no_exceptions( $chkservd_conf, "$service:1\n", 0644 );
        return 1;
    }
    while ( my $line = <$fh> ) {
        if ( $line =~ m/^$service\:1/ ) {
            close $fh;
            return;
        }
    }
    close $fh;
    if ( !Cpanel::FileUtils::Lines::appendline( $chkservd_conf, "$service:1" ) ) {
        warn "Unable to configure chkservd for $service";
    }
    return 1;
}

sub _dnsonly {
    my $self           = shift;
    my $restart_daemon = undef;
    my $etc_chkservd   = '/etc/chkserv.d';
    my $trigger_restart;

    $restart_daemon = _dnsonly_remove_old_files();

    _dnsonly_touch_files();

    $trigger_restart = _write_simple_chkservd_driver('cpsrvd');
    $restart_daemon ||= $trigger_restart;
    $trigger_restart = _write_simple_chkservd_driver('named');
    $restart_daemon ||= $trigger_restart;

    my $cpanellogd_driver = "$etc_chkservd/cpanellogd";
    if ( -e $cpanellogd_driver ) {
        unlink $cpanellogd_driver;
        $restart_daemon = 1;
    }

    return $restart_daemon;
}

sub perform {
    my $self           = shift;
    my $restart_daemon = undef;

    my $is_first_install = -e '/var/cpanel/version/chkservd' ? 0 : 1;

    print Cpanel::SafeRun::Simple::saferun('/usr/local/cpanel/bin/chkservd-install');

    my $etc_chkservd = '/etc/chkserv.d';
    if ( !-d $etc_chkservd ) {
        if ( -e $etc_chkservd
            && !Cpanel::FileUtils::Link::safeunlink($etc_chkservd) ) {
            warn 'Failed to unlink chkservd configuration';
        }

        mkdir $etc_chkservd;
        $restart_daemon = 1;
    }

    chmod 0755, $etc_chkservd;

    my $var_chkservd = '/var/run/chkservd';
    if ( !-d $var_chkservd ) {
        if (   !-e $var_chkservd
            && !Cpanel::FileUtils::Link::safeunlink($var_chkservd) ) {
            warn 'Failed to remove chkservd from var';
        }

        $restart_daemon = 1;
    }

    # here as a safety
    $restart_daemon = 1 if $is_first_install;

    my $trigger_restart;
    foreach my $old_service (qw{webmail cpanel whostmgr entropychat interchange tomcat}) {
        $trigger_restart = _remove_old_service($old_service);
        $restart_daemon ||= $trigger_restart;
    }

    my $cpservd      = '/etc/chkserv.d/cpsrvd';
    my $cpservd_dist = '/usr/local/cpanel/src/chkservd/chkserv.d/cpsrvd';

    if ( !-e $cpservd
        || _are_different( $cpservd, $cpservd_dist ) ) {
        if ( !Cpanel::FileUtils::Copy::safecopy( $cpservd_dist, $etc_chkservd ) ) {
            warn 'Failed to copy cpsrvd configuration from distribution';
        }

        $restart_daemon = 1;
    }

    $trigger_restart = _update_service( 'cpop', 'pop' );
    $restart_daemon ||= $trigger_restart;
    $trigger_restart = _update_service( 'postgres', 'postgresql' );
    $restart_daemon ||= $trigger_restart;
    $trigger_restart = _update_service( 'cpimap', 'imap' );
    $restart_daemon ||= $trigger_restart;
    $trigger_restart = _update_service( 'bind', 'named' );
    $restart_daemon ||= $trigger_restart;

    $trigger_restart = _update_queueprocd();
    $restart_daemon ||= $trigger_restart;

    $trigger_restart = _killall_and_remove('eximstats');
    $restart_daemon ||= $trigger_restart;
    $trigger_restart = _killall_and_remove('antirelayd');
    $restart_daemon ||= $trigger_restart;

    if ( $self->dnsonly() ) {
        $trigger_restart = $self->_dnsonly();
        $restart_daemon ||= $trigger_restart;
    }
    else {
        $trigger_restart = _update_service('cpanellogd');
        $restart_daemon ||= $trigger_restart;
    }

    # restart daemon + install drivers the first time
    _restart_daemon() if $restart_daemon;

    # drivers will not be available before the first call to restart_daemon
    if ($is_first_install) {
        Cpanel::Services::monitor_enabled_services();
        _restart_daemon();
    }

    return 1;
}

1;

__END__
