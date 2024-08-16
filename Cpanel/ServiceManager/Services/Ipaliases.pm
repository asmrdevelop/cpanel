package Cpanel::ServiceManager::Services::Ipaliases;

# cpanel - Cpanel/ServiceManager/Services/Ipaliases.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::Exception            ();
use Cpanel::ServiceManager::Base ();
extends 'Cpanel::ServiceManager::Base';

use Cpanel::Ips        ();
use Cpanel::Ips::Fetch ();

has '+is_cpanel_service' => ( is => 'ro', default => 1 );
has '+service_binary'    => ( is => 'ro', default => '/usr/local/cpanel/whostmgr/bin/ipaliases' );
has '+startup_args'      => ( is => 'ro', lazy    => 1, default => sub { [qw{ start }] } );
has '+restart_args'      => ( is => 'ro', lazy    => 1, default => sub { [qw{ restart }] } );
has '+shutdown_args'     => ( is => 'ro', lazy    => 1, default => sub { [qw{ stop }] } );

has '+can_check_service_status' => ( is => 'ro', default => 0 );

our $MAINIP_FILE = q{/var/cpanel/mainip};
our $IPS_FILE    = q{/etc/ips};

sub is_up {
    my $self = shift;

    # on init.d based systems there's no way to know whether this is up or down ... #
    return 1 if ref( $self->service_manager() ) eq 'Cpanel::ServiceManager::Manager::Initd';
    return $self->SUPER::is_up(@_);
}

sub start_check {
    my $self = shift;

    # need to be sure that mainip is there
    return -e $MAINIP_FILE ? 1 : 0;
}

sub restart {
    my $self = shift;

    # Don't bother unless it is enabled
    die Cpanel::Exception::create( 'Services::Disabled', [ 'service' => 'ipaliases' ] ) if !$self->is_enabled();

    # Similarly, nothing to do if it is not configured.
    die Cpanel::Exception::create( 'Services::NotConfigured', [ 'service' => 'ipaliases' ] ) if !_is_configured();

    # there is no "up" status, so we'll just "stop" (to make sure IPs are removed) and then "start" #
    $self->check_sanity();
    $self->stop() if $self->is_up();
    return $self->start();
}

# XXX Not sure what actually goes down this codepath for ipaliases.
# We actually disable checks via the 'can_check_service_status' flag above.
sub check {
    my ($self) = @_;
    return ( $self->check_with_message() )[0];
}

sub check_with_message {
    my $self = shift;

    # checkservd monitor ipaliases and when the service is disabled, that's fine

    return ( 1, "The 'ipaliases' service is not enabled\n" ) if !$self->is_enabled();
    return ( 1, "No IP aliases are configured\n" )           if !_is_configured();

    return ( 0, $self->status() ) if !$self->SUPER::check(@_);

    my $current_ips_ref    = Cpanel::Ips::Fetch::fetchipslist();
    my $configured_ips_ref = Cpanel::Ips::load_configured_ips();

    foreach my $ip ( keys %{$configured_ips_ref} ) {
        if ( !defined $current_ips_ref->{$ip} ) {
            my $msg = "The 'ipaliases' service has determined there are one ($ip) or more missing IP addresses on the system.";
            $self->logger()->warn($msg);
            die Cpanel::Exception::create( 'Service::IsDown', [ 'service' => 'ipaliases', 'message' => $msg ] );
        }
    }

    return ( 1, "All aliases are configured\n" );
}

# This used to be 'is_enabled', but that's not quite true. These aren't the same thing.
sub _is_configured {
    return ( -f $IPS_FILE && !( -z _ ) ? 1 : 0 );
}

1;
