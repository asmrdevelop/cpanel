package Cpanel::Event::Timer;

# cpanel - Cpanel/Event/Timer.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub new {
    my ( $class, %opts ) = @_;

    die('No event interval specified')       unless defined $opts{'interval'};
    die('No timer alarm callback specified') unless defined $opts{'alarm'};
    die('Alarm callback is not a CODE ref')  unless ref( $opts{'alarm'} ) eq 'CODE';

    if ( defined $opts{'start'} ) {
        die('Timer start callback is not a CODE ref') unless ref( $opts{'start'} ) eq 'CODE';
    }

    if ( defined $opts{'stop'} ) {
        die('Timer stop callback is not a CODE ref') unless ref( $opts{'stop'} ) eq 'CODE';
    }

    return bless {
        'interval' => $opts{'interval'},
        'context'  => $opts{'context'} ? $opts{'context'} : {},
        'alarm'    => $opts{'alarm'},
        'start'    => $opts{'start'},
        'stop'     => $opts{'stop'},
        'running'  => 0,
        'time'     => time()
    }, $class;
}

sub start {
    my ($self) = @_;

    $self->{'running'} = 1;

    if ( defined $self->{'start'} ) {
        return $self->{'start'}->( $self->{'context'} );
    }

    return;
}

sub stop {
    my ($self) = @_;

    $self->{'running'} = 0;

    if ( defined $self->{'stop'} ) {
        return $self->{'stop'}->( $self->{'context'} );
    }

    return;
}

sub running {
    my ($self) = @_;

    return $self->{'running'} ? 1 : 0;
}

sub tick {
    my ($self) = @_;

    my $now = time();

    return if !$self->{'running'} || ( $now - $self->{'time'} ) < $self->{'interval'};

    $self->{'time'} = $now;

    return $self->{'alarm'}->( $self->{'context'} );
}

1;
