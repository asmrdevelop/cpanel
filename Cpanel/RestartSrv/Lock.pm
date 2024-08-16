package Cpanel::RestartSrv::Lock;

# cpanel - Cpanel/RestartSrv/Lock.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Destruct::DestroyDetector';

our $LOCK_BASE = '/var/run/restartsrv';

use Cpanel::FileUtils::Flock  ();
use Cpanel::TimeHiRes         ();
use Cpanel::Exception         ();
use Cpanel::Validate::Service ();

use constant {
    _POLL_INTERVAL => 0.25,
    _LOCK_TIMEOUT  => 196,
};

sub new {
    my ( $class, $service ) = @_;

    die "need service name!" if !$service;

    my $run_lock_file = get_run_lock_file_for_service($service);

    open my $fh, '>>', $run_lock_file or do {
        die "Failed to create lock file “$run_lock_file”: $!";
    };

    _wait_for_ex_lock( $fh, _LOCK_TIMEOUT() ) or do {
        die sprintf( "Restart failed: timeout (%s seconds) reached!", _LOCK_TIMEOUT() );
    };

    my $lock_obj = {
        '_file' => $run_lock_file,
        '_fh'   => $fh,
    };

    return bless $lock_obj, $class;
}

sub _wait_for_ex_lock {
    my ( $fh, $timeout ) = @_;

    my $end = time + $timeout;

    while ( time < $end ) {
        return 1 if Cpanel::FileUtils::Flock::flock( $fh, 'NB', 'EX' );

        Cpanel::TimeHiRes::sleep( _POLL_INTERVAL() );
    }

    return undef;
}

sub release {
    my ($self) = @_;

    delete $self->{'_fh'};

    return 1;
}

sub get_run_lock_file_for_service {
    my ($service) = @_;

    if ( !Cpanel::Validate::Service::is_valid($service) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid service name.', [$service] );
    }

    return $LOCK_BASE . '_' . $service;
}

1;
