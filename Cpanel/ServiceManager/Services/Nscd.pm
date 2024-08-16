package Cpanel::ServiceManager::Services::Nscd;

# cpanel - Cpanel/ServiceManager/Services/Nscd.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Moo;
use Cpanel::ServiceManager::Base ();
use Cpanel::FindBin              ();

extends 'Cpanel::ServiceManager::Base';

has '+service_package' => ( is => 'ro', default => 'nscd' );
has '+pidfile'         => ( is => 'ro', default => '/var/run/nscd/nscd.pid' );

has '+service_binary' => (
    is      => 'ro',                                      # .
    lazy    => 1,                                         # .
    default => sub { Cpanel::FindBin::findbin('nscd') }
);

our $RUN_LOCK_FILE = '/var/lock/subsys/nscd';

sub start {
    my $self = shift;

    $self->remove_dead_lock_file();
    return $self->SUPER::start(@_);
}

sub remove_dead_lock_file {
    my ($self) = @_;

    # If the service is offline and there is a stale
    # run file, we must remove it or the service
    # will not startup
    if ( -e $RUN_LOCK_FILE ) {
        return unlink($RUN_LOCK_FILE) if !$self->is_up();
    }
    return;
}

1;
