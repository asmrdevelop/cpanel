package Cpanel::ServiceManager::Services::Crond;

# cpanel - Cpanel/ServiceManager/Services/Crond.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::ServiceManager::Base ();
use Cpanel::RestartSrv::Systemd  ();
use Cpanel::OS                   ();
extends 'Cpanel::ServiceManager::Base';

my $cron_service = Cpanel::OS::systemd_service_name_map()->{'crond'} || 'crond';
has '+command_line_regex' => ( is => 'ro', lazy    => 1, default => sub { qr/(?-i)\Q$cron_service\E(?i)/ } );
has '+doomed_rules'       => ( is => 'ro', lazy    => 1, builder => 1 );
has '+service_binary'     => ( is => 'ro', default => Cpanel::OS::cron_bin_path() );
if ( $cron_service && $cron_service ne 'crond' ) {
    has '+service_override' => ( is => 'ro', lazy => 1, default => sub { return $cron_service } );
}

sub _build_doomed_rules {
    my ($self) = @_;

    return if Cpanel::RestartSrv::Systemd::has_service_via_systemd($cron_service);
    return if $ENV{'SSH_TTY'} || $ENV{'SSH_CLIENT'};

    return [ $self->service_binary() ];
}

1;
