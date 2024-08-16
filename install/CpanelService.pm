package Install::CpanelService;

# cpanel - install/CpanelService.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw( Cpanel::Task );

use Cpanel::Init::Simple ();
use Cpanel::OS           ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Update and enable cpanel service.

    We do not restart cPanel here
    because this will be done right
    at the end of post_sync_cleanup in "Starting cPanel"

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

    $self->set_internal_name('cpanelservice');
    $self->add_dependencies(qw(pre users));

    return $self;
}

sub perform {
    my $self = shift;

    mkdir '/usr/local/cpanel/logs';

    # remove cpanel service on a non systemd service
    if ( Cpanel::OS::is_systemd() ) {

        # install dnsonly service
        # on Systemd systems dnsonly or cpanel are both using the cpanel service
        #   subservices are using a 'ConditionPathExists=!/var/cpanel/dnsonly' check
        Cpanel::Init::Simple::call_cpservice_with( 'cpanel'            => qw/install enable/ );
        Cpanel::Init::Simple::call_cpservice_with( 'cpanelquotaonboot' => qw/install enable/ );
    }
    else {
        # we should disable + uninstall the service on CloudLinux 6
        #   but we preserve the original behavior
        if ( $self->dnsonly() ) {
            if ( Cpanel::Init::Simple::check_if_cpservice_exists('cpanel') ) {
                Cpanel::Init::Simple::call_cpservice_with( 'cpanel' => qw/disable/ );
            }
            Cpanel::Init::Simple::call_cpservice_with( 'dnsonly' => qw/install enable/ );
        }
        else {
            if ( Cpanel::Init::Simple::check_if_cpservice_exists('dnsonly') ) {
                Cpanel::Init::Simple::call_cpservice_with( 'dnsonly' => qw/disable/ );
            }
            Cpanel::Init::Simple::call_cpservice_with( 'cpanel' => qw/install enable/ );
        }

    }

    return 1;
}

1;

__END__
