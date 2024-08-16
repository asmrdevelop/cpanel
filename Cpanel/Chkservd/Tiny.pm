package Cpanel::Chkservd::Tiny;

# cpanel - Cpanel/Chkservd/Tiny.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::FileUtils::Write          ();
use Cpanel::Chkservd::Tiny::Suspended ();
use Cpanel::LoadFile                  ();

our $VERSION             = '0.7';
our $chkservd_conf       = '/etc/chkserv.d/chkservd.conf';
our $service_suspend_dir = '/var/run/chkservd.services_suspend';

my $DEFAULT_SUSPENSION_DELAY = 70;
my $MAX_SUSPENSION_DELAY     = 3600;

*is_suspended = *Cpanel::Chkservd::Tiny::Suspended::is_suspended;

sub load_service_suspensions {
    my $suspend = {};

    if ( opendir( my $dh, $service_suspend_dir ) ) {
        foreach my $service ( grep ( !m/^[.]/, readdir($dh) ) ) {
            my $expire_time = Cpanel::LoadFile::loadfile( _service_suspend_file($service) );
            $suspend->{$service} = $expire_time;
        }
    }

    return if !scalar keys %{$suspend};
    return $suspend;
}

sub suspend_service {
    my ( $service, $delay, $now ) = @_;
    $delay ||= $DEFAULT_SUSPENSION_DELAY;
    $now   ||= time;
    $delay = $MAX_SUSPENSION_DELAY if $delay > $MAX_SUSPENSION_DELAY;

    _create_dir_if_needed() or return;

    return Cpanel::FileUtils::Write::overwrite_no_exceptions( _service_suspend_file($service), ( $now + $delay ), 0600 );
}

sub is_service_suspended {
    my ( $suspend, $service ) = @_;

    return unless $suspend && $service;

    my $service_file = _service_suspend_file($service);

    my $expire_time = $suspend->{$service} || Cpanel::LoadFile::loadfile($service_file);

    return if !$expire_time;

    return time() < $expire_time ? 1 : 0;
}

sub resume_service {
    my ($service) = @_;

    return unlink( _service_suspend_file($service) );
}

sub _service_suspend_file {
    my ($service) = @_;

    die "A service may not contain a “/” character." if $service =~ m{/};

    return "$service_suspend_dir/$service";
}

sub _create_dir_if_needed {
    if ( !-e $service_suspend_dir ) {
        if ( mkdir( $service_suspend_dir, 0700 ) ) {
            return 1;
        }

        # Cannot logger because the ::Tiny module requirements
        # prevent us from brigging in Cpanel::Logger
        warn "Failed to create “$service_suspend_dir”: $!";
        return;
    }
    else {
        return 1;
    }
    return;
}

1;
