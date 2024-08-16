package Install::Conf;

# cpanel - install/Conf.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw( Cpanel::Task );

use Cpanel::SafeRun::Simple      ();
use Cpanel::SafetyBits           ();
use Cpanel::FileUtils::Lines     ();
use Cpanel::FileUtils::Copy      ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::ConfigFiles          ();
use File::Find                   ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Create multiple directories and adjust their permissions.
    Ensure cpanel and ftp users exist.
    Add nobody to /etc/cron.deny
    Setup /etc/stats.conf

    Run:
    - bin/updatephpmyadmin
    - bin/updateeximstats (not on fresh install)
    - bin/chmodhttpdconf

    Adjust files owner for files from /usr/local/cpanel/var/serviceauth
    Copy cPanel branding files.

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

    $self->set_internal_name('conf');
    $self->add_dependencies(qw{default_feature_files users});

    return $self;
}

#TODO: Error handling
sub _mkdirs {
    my %perms = @_;

    if ( !%perms ) {
        %perms = (
            '/etc/cpanel'                                   => 0751,
            '/var/cpanel'                                   => 0711,
            '/var/cpanel/mgmt_queue'                        => 0711,
            '/var/cpanel/overquota'                         => 0711,
            $Cpanel::ConfigFiles::PACKAGES_DIR              => 0700,
            $Cpanel::ConfigFiles::cpanel_users              => 0711,
            $Cpanel::ConfigFiles::cpanel_users_cache        => 0711,
            $Cpanel::ConfigFiles::BANDWIDTH_DIRECTORY       => 0711,
            $Cpanel::ConfigFiles::BANDWIDTH_CACHE_DIRECTORY => 0711,
            '/var/cpanel/backups'                           => 0750,
            '/var/cpanel/webmail'                           => 0755,
            '/var/cpanel/zonetemplates'                     => 0755,
            '/usr/local/cpanel/logs'                        => 0711,
            '/usr/local/cpanel/var'                         => 0711,
            '/usr/local/cpanel/var/serviceauth'             => 0711,
            '/usr/local/cpanel/var/serviceauth/cur'         => 0711,
            '/usr/local/cpanel/var/serviceauth/tmp'         => 0711,
            '/usr/local/cpanel/var/serviceauth/new'         => 0711,
        );
    }

    foreach my $dir ( sort keys %perms ) {
        if ( !-e $dir ) {
            mkdir $dir;
            chmod $perms{$dir}, $dir;
        }
        else {
            chmod $perms{$dir}, $dir;
        }
    }

    return 1;
}

sub _chown_cpusers {
    require '/usr/local/cpanel/bin/chowncpusers';    ##no critic qw(RequireBarewordIncludes)
    bin::chowncpusers->script('--quiet');
    return 1;
}

sub _make_chown_closure {
    my $user  = shift;
    my $group = shift;

    my $s = sub {
        Cpanel::SafetyBits::safe_chown( $user, $group, $File::Find::name );
    };

    return $s;
}

sub _mkdir_cpanel_owned {
    my $dir = shift;

    if ( !-e $dir ) {
        mkdir $dir;
    }

    File::Find::find( _make_chown_closure( 'cpanel', 'cpanel' ), $dir );
    return 1;
}

sub _deny_access_to_nobody {
    if (   !Cpanel::FileUtils::Lines::has_txt_in_file( '/etc/cron.deny', 'nobody' )
        && !Cpanel::FileUtils::Lines::appendline( '/etc/cron.deny', 'nobody' ) ) {
        warn 'Failed to deny access to cron by nobody';
        return;
    }

    return 1;
}

sub _touch_upcpcheck {
    if ( !Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/upcpcheck') ) {
        warn 'Failed to flag upcpcheck';
        return;
    }

    return 1;
}

sub _copy_stats_conf {
    my $src  = '/usr/local/cpanel/etc/stats.conf';
    my $dest = '/etc/stats.conf';

    if ( !-e $dest ) {
        Cpanel::FileUtils::Copy::safecopy( $src, $dest );
        chmod( 0644, $dest );
    }
    return;
}

sub run_and_print {
    my (@cmd) = @_;
    my $out = Cpanel::SafeRun::Simple::saferun(@cmd);
    print $out if defined $out;
    return;
}

sub perform {
    my $self = shift;

    _mkdirs();
    _chown_cpusers();
    _copy_stats_conf();

    run_and_print('/usr/local/cpanel/bin/updatephpmyadmin');

    if ( !$ENV{'CPANEL_BASE_INSTALL'} ) {
        local $@;
        require '/usr/local/cpanel/bin/updateeximstats';    ##no critic qw(RequireBarewordIncludes)
        eval { bin::updateeximstats->run(); };

        # the second program is useless if the first fails

        no warnings 'once';
        require Cpanel::EximStats::ImportInProgress;
        if ( !$@ && !-e $Cpanel::EximStats::ImportInProgress::IMPORTED_FILE ) {
            run_and_print('/usr/local/cpanel/scripts/slurp_exim_mainlog');
        }
    }

    File::Find::find(
        _make_chown_closure( 'cpanel', 'cpanel' ),
        '/usr/local/cpanel/var/serviceauth'
    );

    require '/usr/local/cpanel/bin/chmodhttpdconf';    ##no critic qw(RequireBarewordIncludes)
    bin::chmodhttpdconf->script();

    _deny_access_to_nobody();

    if ( -l '/var/cpanel/cpanelbranding' ) {
        print "Skipping cpanelbranding update because it is a symlink\n";
    }
    else {

        # symlink is missing
        # copy directory content to userhomes + remove dir
        if ( -d '/var/cpanel/cpanelbranding' ) {

            # check permissions before copying any files
            _mkdir_cpanel_owned("$Cpanel::ConfigFiles::ROOT_CPANEL_HOMEDIR/cpanelbranding");
            system "cp -Rp /var/cpanel/cpanelbranding/* $Cpanel::ConfigFiles::ROOT_CPANEL_HOMEDIR/cpanelbranding";
            system 'rm', '-rf', '/var/cpanel/cpanelbranding';
        }

        # create symlink
        symlink "$Cpanel::ConfigFiles::ROOT_CPANEL_HOMEDIR/cpanelbranding", '/var/cpanel/cpanelbranding' unless -e '/var/cpanel/cpanelbranding';
    }

    # make sure permissions are correct ( need to be done twice when directory already exist )
    _mkdir_cpanel_owned("$Cpanel::ConfigFiles::ROOT_CPANEL_HOMEDIR/cpanelbranding");

    chmod( 0711, "/var/cpanel/userhomes" );

    _mkdir_cpanel_owned('/var/cpanel/tmp');
    _touch_upcpcheck();

    {    # touch cpanel.config to purge the cache on updates
        my $cpconf = $Cpanel::ConfigFiles::cpanel_config_file;
        Cpanel::FileUtils::TouchFile::touchfile($cpconf) if -e $cpconf;
    }

    return 1;
}

1;

__END__
