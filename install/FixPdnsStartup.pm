package Install::FixPdnsStartup;

# cpanel - install/FixPdnsStartup.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use parent qw( Cpanel::Task );

use cPstrict;

use Cpanel::Config::LoadCpConf ();
use Cpanel::Init               ();
use Cpanel::Services::Enabled  ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    This task runs if it is detected that PowerDNS is enabled but not configured to start at system boot.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new ($proto) {
    my $self = $proto->SUPER::new;

    $self->set_internal_name('fix_pdns_startup');

    return $self;
}

sub perform ($self) {
    return 1 if $ENV{'CPANEL_BASE_INSTALL'};

    # Being "enabled" here does not mean that the service will start at boot, only that the service is not disabled.
    return 1 unless Cpanel::Services::Enabled::is_enabled('dns');

    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    return 1 unless defined $cpconf_ref->{'local_nameserver_type'} && $cpconf_ref->{'local_nameserver_type'} eq 'powerdns';

    my $init = Cpanel::Init->new();

    # Start PDNS unless it's already running.
    $init->run_command( 'pdns', 'start' ) unless $init->run_command( 'pdns', 'status' )->{'status'};

    # Being "enabled" here means that the service is configured to start at boot, otherwise it needs to be fixed.
    return 1 if $init->enabler()->is_enabled('pdns');

    print "The pdns (PowerDNS) service is enabled but is not configured to start on boot.\n";
    if ( $init->run_command_for_one( 'enable', 'pdns' ) ) {
        print "The system successfully configured the pdns service to start on boot.\n";
    }
    else {
        print "The system failed to configure the pdns service to start on boot.\n";
        return 0;
    }

    return 1;
}

1;

__END__
