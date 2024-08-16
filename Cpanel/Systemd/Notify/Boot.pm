package Cpanel::Systemd::Notify::Boot;

# cpanel - Cpanel/Systemd/Notify/Boot.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Sys::Boot ();

use parent qw ( Cpanel::Systemd::Notify );

=encoding utf-8

=head1 NAME

Cpanel::Systemd::Notify::Boot

=head1 SYNOPSIS

    use Cpanel::Logger ();
    use Cpanel::Systemd::Notify::Boot ();

    my $logger = Cpanel::Logger->new();

    sdnotify()->enable() if grep { /^--systemd/ } @ARGV;

    # ... get ready to do things ...
    # ... But, if the server is booting, we must wait until boot is finished before performing any further actions ...
    sdnotify()->ready_and_wait_for_boot_to_finish(
        {
            # logs 'Waiting for the system to finish booting...', if a boot wait occurs.
            'waiting_callback' => sub ($msg) { $logger->info($msg) },
        }
    );

    if ($got_reload_signal) {
        sdnotify()->reloading();
        # ... do reloading things ...
        sdnotify()->ready();
    }

    if ($got_stop_signal) {
        sdnotify()->stopping();
        # ... perform cleanup ...
        exit;
    }

    sub sdnotify {
        return Cpanel::Systemd::Notify::Boot->get_instance( 'service' => 'myservice' );
    }

=head1 DESCRIPTION

This module extends the base class L<Cpanel::Systemd::Notify> with methods that pertain to systemd notifications and the boot sequence.

See the L<Cpanel::Systemd::Notify> POD for more detailed information about systemd notifications.

=head1 FUNCTIONS

=head2 ready_and_wait_for_boot_to_finish(OPTIONS)

Sends a ready notification to systemd and then checks if the system has finished booting.
If the system has NOT finished booting, the human-readable unit status string is updated to indicate waiting and an optional callback code ref is executed, then it waits until the system indicates that the boot sequence is complete.
If a wait occurred then the systemd unit status is updated to a ready status again.

The ready notification occurs before waiting so that the boot sequence can proceed.
Otherwise, systemd will be waiting on the service to become ready and it can not proceed until the unit startup timeout occurs.

The wait for boot to finish and the optional callback works whether or not C<enable()> has been called, so it is also useful on non-systemd systems.

Returns the object reference.

=head3 ARGUMENTS

=over

=item OPTIONS - hash

Where the following named options may be provided:

=over

=item waiting_status - string

See L<Cpanel::Systemd::Notify/"status($status)"> for details.
Default is B<Waiting for the system to finish booting...>

=item ready_status - string

See L<Cpanel::Systemd::Notify/"status($status)"> for details.
Default is the same as L<Cpanel::Systemd::Notify/"ready()">.

=item wait_callback - code ref

A code ref which is called once and passed the C<waiting_status> string if a wait occurs.
For example, use it to send the C<waiting_status> string to the service's logger.

=back

=back

=cut

sub ready_and_wait_for_boot_to_finish ( $self, $OPTS = {} ) {
    die 'Named options must be a hash reference.' unless ref $OPTS eq 'HASH';

    my $ready_status     = $OPTS->{'ready_status'};
    my $waiting_status   = $OPTS->{'waiting_status'} // 'Waiting for the system to finish booting...';
    my $waiting_callback = $OPTS->{'waiting_callback'};
    die "The “waiting_callback” option must be a code reference." if $waiting_callback && ref $waiting_callback ne 'CODE';

    $self->ready($ready_status);

    my $waited;
    while ( $self->_is_booting() ) {
        if ( !$waited ) {
            ++$waited;
            $self->status($waiting_status);
            $waiting_callback->($waiting_status) if $waiting_callback;
        }
        sleep _BOOT_WAIT_SLEEP_SECONDS();
    }
    $self->ready($ready_status) if $waited;
    return $self;
}

#----------------------------------------------------------------------

# Mockable constant
sub _BOOT_WAIT_SLEEP_SECONDS {
    return 5;
}

sub _is_booting ($self) {
    return Cpanel::Sys::Boot::is_booting();
}

1;
