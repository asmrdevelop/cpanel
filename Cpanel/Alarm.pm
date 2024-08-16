package Cpanel::Alarm;

# cpanel - Cpanel/Alarm.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This module provides an easy interface to introduce a temporary alarm that is
# automatically cleaned up as it goes out of scope.

use strict;
use warnings;

use Cpanel::Destruct ();

sub new {
    my $class              = shift or die("Cpanel::Alarm::new is a method call.");
    my $local_alarm_length = shift || 0;
    my $action             = shift;

    my $self = bless( {}, $class );

    # Setup the alarm.
    $self->{'previous_alarm_time_left'} = $self->set($local_alarm_length);

    $self->{'creation_time'}   = $self->{'local_alarm_start'};
    $self->{'previous_action'} = $SIG{'ALRM'};

    # Localize $SIG{ALRM}
    if ( defined $action ) {
        $SIG{'ALRM'} = $action;
    }
    return $self;
}

sub get_length { return shift->{'local_alarm_length'} }

sub set {    ## no critic qw(Unpack)
    $_[0] or die 'Need argument!';
    $_[0]->{'local_alarm_length'} = $_[1];
    $_[0]->{'local_alarm_start'}  = time();

    if ( $_[1] =~ tr<.><> ) {

        # This should normally only happen in tests.
        require Time::HiRes;
        return Time::HiRes::alarm( $_[1] );
    }

    return alarm( $_[1] );    # This is the total length of the alarm since new()
}

sub get_remaining {
    my $self = shift or die;
    return ( $self->{'local_alarm_length'} - ( time - $self->{'local_alarm_start'} ) );
}

sub DESTROY {
    my $self = shift or return;

    return if Cpanel::Destruct::in_dangerous_global_destruction();

    # Restore the previous signal handler always.
    $SIG{'ALRM'} = $self->{'previous_action'} || 'DEFAULT';

    alarm(0);

    # Nothing else to do if there was no previous alarm.
    return if ( !$self->{'previous_alarm_time_left'} );

    my $new_alarm = int( $self->{'previous_alarm_time_left'} - ( time() - $self->{'creation_time'} ) );

    # If the alarm should have gone off while we were in control. Set it off now.
    # Othewise restore the previous alarm with time elapsed.
    ( $new_alarm <= 0 ) ? alarm(1) : alarm($new_alarm);
}

1;
