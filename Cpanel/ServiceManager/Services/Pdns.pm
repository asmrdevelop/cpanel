package Cpanel::ServiceManager::Services::Pdns;

# cpanel - Cpanel/ServiceManager/Services/Pdns.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
extends 'Cpanel::ServiceManager::Base';

use Cpanel::ServiceManager::Base ();
use Cpanel::Binaries             ();
use Cpanel::TimeHiRes            ();
use Cpanel::OS                   ();

has '_use_powerdns' => ( is => 'ro', lazy => 1, builder => 1 );

has '+service_binary'  => ( is => 'ro', default => Cpanel::Binaries::path('pdns_server') );
has '+service_package' => ( is => 'ro', default => 'cpanel-pdns' );
has '+processowner'    => ( is => 'ro', default => 'named' );

has '+pidfile'            => ( is => 'ro', lazy    => 1, default => sub { !Cpanel::OS::is_systemd() ? '/var/run/pdns/pdns.pid' : undef } );
has '+doomed_rules'       => ( is => 'ro', lazy    => 1, default => sub { [ 'named', 'pdns_server' ] } );
has '+ports'              => ( is => 'ro', lazy    => 1, builder => 1 );
has '+service_to_suspend' => ( is => 'ro', default => 'named' );
has '+is_configured'      => ( is => 'ro', lazy    => 1, default => sub { return $_[0]->_use_powerdns                                             ? 1 : 0 } );
has '+is_enabled'         => ( is => 'ro', lazy    => 1, default => sub { return 0 unless $_[0]->_use_powerdns; return $_[0]->SUPER::is_enabled() ? 1 : 0 } );

use constant USE_POWERDNS_FILE => q{/var/cpanel/usepowerdns};

sub _build__use_powerdns {
    my ($self) = @_;

    if ( !-e USE_POWERDNS_FILE ) {
        $self->debug( "Missing file: " . USE_POWERDNS_FILE );
        return;
    }

    if ( $self->cpconf->{'local_nameserver_type'} eq 'powerdns' ) {
        return 1;
    }
    else {
        $self->debug('local_nameserver_type is not set to powerdns in cpanel.config');
        return;
    }
}

sub _build_ports {
    my ($self) = @_;

    my $ports = [53];

    #Forcibly configure pdns to have a reserved port, among other things
    require Cpanel::SafeRun::Object;
    my $run = Cpanel::SafeRun::Object->new( program => '/usr/local/cpanel/scripts/migrate-pdns-conf', args => [] );
    if ( $run->CHILD_ERROR() ) {
        require Cpanel::Debug;
        Cpanel::Debug::log_warn( "Failed to apply the PowerDNS configuration: " . $run->stderr() );
    }

    require Cpanel::NameServer::Conf::PowerDNS::WebserverAPI;
    my $conf = Cpanel::NameServer::Conf::PowerDNS::WebserverAPI::_load_config();
    if ( $conf->{'webserver-port'} && $conf->{'webserver-port'} =~ /^[0-9]+$/ ) {

        # Now kill anything still running on the port.
        require Cpanel::Kill::AppPort;
        Cpanel::Kill::AppPort::kill_apps_on_ports(
            'ports'   => [ int( $conf->{'webserver-port'} ) ],
            'verbose' => $Cpanel::Kill::AppPort::VERBOSE,
        );

        push( @{$ports}, int( $conf->{'webserver-port'} ) );
    }

    return $ports;
}

sub pidfile_precheck {

    # Read the file after a few milliseconds, to give the process time to write
    # and flush the pidfile.  This is required for PowerDNS to reliably report
    # its state.  This should be mocked in tests if need be instead of removed.
    return Cpanel::TimeHiRes::sleep(0.5);
}

1;
