package Install::NscdSystemdCustomConfig;

# cpanel - install/NscdSystemdCustomConfig.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::SafeDir::MK       ();
use Cpanel::OS                ();
use Cpanel::Init              ();
use Cpanel::ServerTasks       ();
use Cpanel::Services::Enabled ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Create/update nscd.service.d/cpanel.conf
    on Systemd systems to start nscd with
    a much higher file descriptor limit

=over 1

=item Type: Systemd, cPanel setup

=item Frequency: Always

    Note: systemctl daemon is not reloaded

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('nscd_systemd_config');
    $self->add_dependencies(qw( taskqueue ));

    return $self;
}

sub _get_nscd_custom_config_dir {
    return '/etc/systemd/system/nscd.service.d';
}

sub _get_custom_config_file_contents {
    return <<END_CONTENT;
[Service]
LimitNOFILE=1048576
END_CONTENT
}

sub perform {
    my $self = shift;

    # Nothing to do if we don't have systemd
    return 1 unless Cpanel::OS::is_systemd();

    # This is the directory where we will place the custom nscd config file
    # which will amend the behavior of the installed nscd unit file
    my $nscd_custom_config_dir = _get_nscd_custom_config_dir();
    Cpanel::SafeDir::MK::safemkdir( $nscd_custom_config_dir, '0755' ) unless -d $nscd_custom_config_dir;

    # Create and populate the unit file
    my $custom_config_file = $nscd_custom_config_dir . '/cpanel.conf';

    # ...but not if the file already exists, since a user could customize this
    if ( !-e $custom_config_file ) {
        if ( open( my $fh, '>', $custom_config_file ) ) {
            print {$fh} _get_custom_config_file_contents();
            close $fh;
        }
        else {
            warn "Unable to open $custom_config_file:  $!";
            return 0;
        }
    }

    Cpanel::Init->new()->enabler()->daemon_reload();
    Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, "restartsrv nscd" ) if Cpanel::Services::Enabled::is_enabled("nscd");

    return 1;
}

1;

__END__
