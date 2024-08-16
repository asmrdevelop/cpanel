package Cpanel::Services::Dormant;

# cpanel - Cpanel/Services/Dormant.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# keep this module Tiny, it's shared among all dormant services
#	with some basic helpers

use strict;
use warnings;

=head1 NAME

Cpanel::Services::Dormant

=head1 SYNOPSIS

     use Cpanel::Services::Dormant      ();

     my $dormant_mode = Cpanel::Services::Dormant->new( service => 'myservice' );

     while ( 1 ) {
        ...
        my @readyfds = IO::Select->select( $read_set, undef, undef, $dormant_mode->idle_timeout() );
        ...
        if ( ! $is_chkservd_query ) {
            $dormant_mode->got_an_active_connection();
        }

        exec 'dormant.pl' if $dormant_mode->should_go_dormant();

     }

=head1 DESCRIPTION

Cpanel::Services::Dormant module provide a set of helpers to use the same
logic in all cpanel services which provide dormant mode.

Currently it's using a time base counter, rather than an incremental counter.
This brings the cost of an additional time() query for each request.

=cut

my $GO_DORMANT_IN_N_MINUTES = {
    'default'  => 10,
    'spamd'    => 15,    # go dormant after 15 minutes when receive no emails
    'cpsrvd'   => 2,
    'dnsadmin' => 5,
};

my $IDLE_TIMEOUT = {
    'default'  => 60,
    'spamd'    => 30,
    'cpsrvd'   => 30,
    'dnsadmin' => 5,
};

# for unit tests
our $DORMANT_SERVICES_DIR = q{/var/cpanel/dormant_services};

=head2 Cpanel::Services::Dormant-E<gt>new( service => q{my-service-name} )

Create a new Cpanel::Services::Dormant object.
service name is mandatory.

=head3 Returns

A blessed reference to a Cpanel::Services::Dormant object.

=cut

sub new {
    my ( $class, %opts ) = @_;

    die "Service must be provided" unless my $service = $opts{service};

    my $self = bless {}, $class;

    $self->{service}     = $service;
    $self->{enable_file} = qq{$DORMANT_SERVICES_DIR/${service}/enabled};
    $self->got_an_active_connection();

    $self->_ensure_dormant_time_will_not_prematurely_killoff_children(%opts);

    # lower the value when debugging (unit test, qa testing....)
    if ( -e qq{$DORMANT_SERVICES_DIR/debug} ) {
        $self->{_idle_timeout}         = 5;
        $self->{_dormant_in_n_minutes} = 0.25;    # 15 sec
    }

    # cache it at creation, we do not want to check it anymore
    $self->{'can_go_dormant'} = -e $self->{enable_file} ? 1 : 0;

    return $self;
}

sub _ensure_dormant_time_will_not_prematurely_killoff_children {
    my ( $self, %opts ) = @_;

    # Call go_dormant_in_n_minutes to populate
    #  $self->{'_dormant_in_n_minutes'}
    $self->go_dormant_in_n_minutes();

    # Currently dnsadmin passes a minimum_idle_timeout which is the timeout
    # of a local request in a child process in order to ensure we do not
    # go dormant and kill off its children while it is still processing
    # a request in the even dormant services tries to set an idle
    # timeout which is shorter then the timeout for a child.
    if ( $opts{'minimum_idle_timeout'} && $opts{'minimum_idle_timeout'} > ( $self->{'_dormant_in_n_minutes'} * 60 ) ) {
        my $minimum_idle_timeout_in_minutes = ( $opts{'minimum_idle_timeout'} / 60 );
        warn "Dormant services attempted to set the idle timeout for the “$opts{service}” to “$self->{'_dormant_in_n_minutes'}” minutes which is lower than the minimum allowed idle timeout of “$minimum_idle_timeout_in_minutes” minutes.";
        $self->{'_dormant_in_n_minutes'} = $minimum_idle_timeout_in_minutes;
        return 0;
    }
    return 1;
}

=head2 $self-E<gt>got_an_active_connection()

Use this function when the service receives an active connection.
The internal timer for the last connection is updated.

=head3 Returns

always return undef

=head3 Notes

We currently only count active connections.
For improvements we could count active and inactive in order to switch to a counter base.

=cut

sub got_an_active_connection {
    my $self = shift;

    # note: we can replace the time system by a counter
    $self->{last_connection} = time();
    return;
}

=head2 $self-E<gt>get_last_connection()

Retrieve the current value of the internal timer for the last connection.

=head3 Returns

Returns a timestamp as an integer

=cut

sub get_last_connection {
    my $self = shift;
    return $self->{last_connection};
}

=head2 $self-E<gt>is_enabled()

Check if the service has dormant mode enabled.

=head3 Returns

Returns a boolean value: 0/1

=cut

sub is_enabled {
    my $self = shift;
    return $self->{'can_go_dormant'};
}

=head2 $self-E<gt>idle_timeout()

Returns the idle_timeout to use for this service when reading from a socket.

=head3 Returns

Returns an integer: number of seconds

=head3 Notes

The main advantage of providing an idle_timeout, is to be able to reduce its value when testing,
while preserving it to a higher value during production.

=cut

sub idle_timeout {
    my $self = shift;

    return $self->{_idle_timeout} if $self->{_idle_timeout};
    $self->{_idle_timeout} = $IDLE_TIMEOUT->{ $self->{'service'} } || $IDLE_TIMEOUT->{'default'};

    return $self->{_idle_timeout};
}

=head2 $self-E<gt>go_dormant_in_n_minutes()

Returns the number of inactive minutes before switching to dormant.

=head3 Returns

Returns a number: can be integer or float

=head3 Notes

Floats are mainly used for testing to use a number of seconds lower than a minute.

=cut

sub go_dormant_in_n_minutes {
    my $self = shift;

    return $self->{_dormant_in_n_minutes} if defined $self->{_dormant_in_n_minutes};

    # default value
    $self->{_dormant_in_n_minutes} = $GO_DORMANT_IN_N_MINUTES->{ $self->{'service'} } || $GO_DORMANT_IN_N_MINUTES->{'default'};

    # the file will contain a 1, which means use the default time, otherwise a positive integer
    # means that is the time before going dormant #
    # the file can also contains a float
    if ( -e $self->{enable_file} ) {
        open my $fh, '<', $self->{enable_file} or die "could not read '': $!";
        my $dormant_time = readline($fh);
        $dormant_time = 1 if !$dormant_time;    # undefined or 0 is not a valid value, auto correct it
        chomp($dormant_time);
        close $fh;

        # reduce by 1 minute, to be able to set 1 as the minimal value
        $self->{_dormant_in_n_minutes} = $dormant_time - 1 if $dormant_time > 1;
    }

    return $self->{_dormant_in_n_minutes};
}

=head2 $self-E<gt>should_go_dormant()

Check if it's time for the service to switch to dormant mode.

=head3 Returns

Returns a boolean value: true / false

=cut

sub should_go_dormant {

    my $self = shift;

    return unless $self->is_enabled();
    return ( time() - $self->get_last_connection() ) >= $self->go_dormant_in_n_minutes() * 60;
}

1;
