package Cpanel::ServiceManager::Services::Cpipv6;

# cpanel - Cpanel/ServiceManager/Services/Cpipv6.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Moo;
extends 'Cpanel::ServiceManager::Base';

has '+startup_args'   => ( is => 'ro', lazy    => 1, default => sub { [qw{ start }] } );
has '+shutdown_args'  => ( is => 'ro', lazy    => 1, default => sub { [qw{ stop }] } );
has '+service_binary' => ( is => 'rw', default => '/usr/local/cpanel/whostmgr/bin/cpipv6' );

use Cpanel::SafeRun::Object ();

sub action_list {
    my ($self) = @_;
    exec $self->service_binary(), 'list';
}

sub status {
    my $self   = shift;
    my $status = Cpanel::SafeRun::Object->new_or_die( 'program' => $self->service_binary(), 'args' => ['status'] )->stdout();
    return $status;
}

sub is_up {
    my $self = shift;
    return $self->status() ? 1 : 0;
}

1;
