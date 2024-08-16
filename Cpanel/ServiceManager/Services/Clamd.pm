package Cpanel::ServiceManager::Services::Clamd;

# cpanel - Cpanel/ServiceManager/Services/Clamd.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::ServiceManager::Base ();
use Cpanel::Binaries             ();
use Cpanel::SafeRun::Simple      ();
use Cpanel::Exception            ();
use Cpanel::TimeHiRes            ();
use Cpanel::OS                   ();
use IO::Handle                   ();

extends 'Cpanel::ServiceManager::Base';

has '_status_maximum_wait_time' => ( is => 'ro', is => 'ro', default => 60 );
has '_cpanel_clamd_conf_file' => ( is => 'ro', default => '/usr/local/cpanel/3rdparty/etc/clamd.conf' );

has '+pidfile' => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        return Cpanel::OS::is_systemd() ? undef : '/var/run/clamd.pid';
    }
);
has '+service_to_suspend' => ( is => 'ro', default => 'clamd' );

has '+service_package' => ( is => 'ro', lazy => 1, default => sub { [ 'cpanel-clamav', 'cpanel-clamav-virusdefs' ] } );
has '+doomed_rules'    => ( is => 'ro', lazy => 1, default => sub { ['clamd'] } );
has '+service_binary'  => ( is => 'ro', lazy => 1, default => sub { Cpanel::Binaries::path('clamd') } );

# Note that clamd does not use one init.script on CentOS 5/6

sub status {
    my ( $self, @args ) = @_;

    # preserve status string from parent
    my $status = $self->SUPER::status(@args);
    return unless $status;

    my $socket = $self->get_socket;

    my $wait_time      = 0.1;
    my $max_iterations = ( int( $self->_status_maximum_wait_time / $wait_time ) || 1 );    # default is 60s
    foreach ( 1 .. $max_iterations ) {
        return $status if -e $socket;
        Cpanel::TimeHiRes::sleep($wait_time) unless $_ == $max_iterations;
    }

    die Cpanel::Exception::create( 'Services::SocketIsMissing', [ service => $self->service, socket => $socket ] );
}

sub restart {
    my ($self) = @_;

    # case CPANEL-17860:
    # A restart needs to fully stop and
    # start clamd to ensure the socket file
    # is in place
    $self->stop();
    $self->start();
    return 1;
}

sub check {
    my ( $self, @args ) = @_;

    return unless my $status = $self->SUPER::check(@args);

    # extra check from legacy script: could be done via one 'rpm -qvV' query
    my $clamdscan = Cpanel::Binaries::path('clamdscan');
    die Cpanel::Exception::create( 'Service::BinaryNotFound', [ service => $clamdscan || 'clamdscan' ] ) if !-x $clamdscan;

    return $status;
}

# this is a duplicate logic with Cpanel::ClamScanner::ClamScanner_getsocket
sub get_socket {
    my $self = shift;

    return $self->_get_socket_from_conf( $self->_get_conf_file );
}

sub _get_conf_file {
    my ($self) = @_;

    if ( !$self->service_binary || !-x $self->service_binary ) {
        die Cpanel::Exception::create( 'Service::BinaryNotFound', [ service => $self->service_binary || 'clamd' ] );
    }

    my $dl = Cpanel::SafeRun::Simple::saferunnoerror( '/usr/bin/strings', $self->service_binary );

    # we probably only want to use /usr/local/cpanel/3rdparty/etc/clamd.conf
    #   as this is the one shipped by the RPM
    if ( $dl && $dl =~ m/^(.*\/clam(?:av|d).conf)/m ) {    # multi-line
        return $1;
    }

    return -e $self->_cpanel_clamd_conf_file ? $self->_cpanel_clamd_conf_file : '/etc/clamd.conf';
}

sub _get_socket_from_conf {
    my ( $self, $conf ) = @_;

    if ( $conf && -e $conf ) {
        my $socket;
        my $read = IO::Handle->new();
        if ( open( $read, "<", $conf ) ) {
            while (<$read>) {
                if (/^[\s\t]*LocalSocket[\s\t]*(\S+)/i) {
                    $socket = $1;
                    last;
                }
            }
            close($read);
        }
        return $socket if $socket;
    }

    # preserve original behavior, always return a value
    return q{/var/clamd};
}

1;
