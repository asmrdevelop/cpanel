package Install::Apache;

# cpanel - install/Apache.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Task );

use File::Path              ();
use Cpanel::SafeRun::Simple ();
use Cpanel::OS              ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::ServerTasks      ();
use Cpanel::FileUtils::Chown ();

our $VERSION = '1.1';

=head1 DESCRIPTION

Apache setup / sanity check

=over 1

=item Type: Software Install, Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('apache');
    $self->add_dependencies(qw( taskqueue ));

    return $self;
}

sub _setup {
    my $self = shift;

    # here as a security, but this will be useful when upgrading from C6 to C7
    if ( Cpanel::OS::is_systemd() && -e "/etc/init.d/httpd" ) {

        # should happen before enabling the service
        unlink "/etc/init.d/httpd";

        # do not need to disable the SysV service, as it will be done for us
        #   when installing the systemd service
        $self->{restart_force} = 1;
    }

    require '/usr/local/cpanel/bin/setupmime';    ##no critic qw(RequireBarewordIncludes)
    bin::setupmime->script();

    require Cpanel::LeechProtect::DB;
    Cpanel::LeechProtect::DB->new->initialize_db();

    return;
}

sub _restart {
    my $self = shift;

    my $task;
    if ( $self->{restart_force} ) {
        $task = 'apache_restart --force';
    }
    else {
        $task = 'apache_restart';
    }

    # On a fresh install this will happen after the install is finish
    # and queueprocd is up and running.  If we do not queue then it will
    # be lost on fresh installs since apache restarts are blocked
    # on fresh installs.
    eval { Cpanel::ServerTasks::queue_task( ['ApacheTasks'], $task ); };
    warn if $@;
    return;
}

sub _includes {
    my $dir = apache_paths_facade->dir_conf_includes();

    if (   !-e $dir
        && !File::Path::mkpath( $dir, { verbose => 1 } ) ) {
        warn 'Failed to make Apache includes directory';
    }

    my @files = (
        'pre_main_global.conf',
        'pre_virtualhost_global.conf',
        'post_virtualhost_global.conf',
        'pre_main_1.conf',
        'pre_virtualhost_1.conf',
        'post_virtualhost_1.conf',
        'pre_main_2.conf',
        'pre_virtualhost_2.conf',
        'post_virtualhost_2.conf'
    );

    foreach my $file (@files) {
        my $full_filename = "$dir/$file";

        Cpanel::FileUtils::Chown::check_and_fix_owner_and_permissions_for(
            'uid'         => 0,
            'gid'         => 0,
            'octal_perms' => 0600,
            'path'        => $full_filename,
            'create'      => 1,
        );

    }

    if ( !-e "$dir/account_suspensions.conf" ) {
        print Cpanel::SafeRun::Simple::saferun( '/usr/local/cpanel/scripts/generate_account_suspension_include', '--update', '--convert', '--verbose' );
    }

    return;
}

sub perform {
    my $self = shift;
    return 1 if $self->dnsonly();

    $self->_setup();
    _includes();
    $self->_restart();

    if ( !-e '/etc/ssldomains' ) {
        print Cpanel::SafeRun::Simple::saferun('/usr/local/cpanel/scripts/updatessldomains');
    }

    return 1;
}

1;

__END__
