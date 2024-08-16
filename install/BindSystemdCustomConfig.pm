package Install::BindSystemdCustomConfig;

# cpanel - install/BindSystemdCustomConfig.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::SafeDir::MK ();
use Cpanel::OS          ();
use Cpanel::Init        ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Create/update named.service.d/cpanel.conf
    on Systemd systems to start named after
    ipaliases and cpiv6 services.

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

    $self->set_internal_name('bind_systemd_config');

    return $self;
}

sub _get_bind_custom_config_dir {
    return '/etc/systemd/system/named.service.d';
}

sub _get_custom_config_file_contents {
    return <<END_CONTENT;
[Unit]
After=ipaliases.service
After=cpipv6.service
END_CONTENT
}

sub perform {
    my $self = shift;

    # Nothing to do if we don't have systemd
    return 1 unless Cpanel::OS::is_systemd();

    # This is the directory where we will place the custom bind config file
    # which will amend the behavior of the installed bind unit file
    my $bind_custom_config_dir = _get_bind_custom_config_dir();
    Cpanel::SafeDir::MK::safemkdir( $bind_custom_config_dir, '0755' ) unless -d $bind_custom_config_dir;

    # Create and populate the unit file
    my $custom_config_file = $bind_custom_config_dir . '/cpanel.conf';

    if ( open( my $fh, '>', $custom_config_file ) ) {
        print {$fh} _get_custom_config_file_contents();
        close $fh;
    }
    else {
        warn "Unable to open $custom_config_file:  $!";
        return 0;
    }

    Cpanel::Init->new()->enabler()->daemon_reload();

    return 1;
}

1;

__END__
