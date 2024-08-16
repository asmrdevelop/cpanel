package Cpanel::TaskProcessors::NotificationTasks::Adder;

# cpanel - Cpanel/TaskProcessors/NotificationTasks/Adder.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::NotificationTasks::Adder

=head1 SYNOPSIS

    Cpanel::TaskProcessors::NotificationTasks::Adder->add( @args );

=head1 DISCUSSION

This is the adder module for the NotificationTasks subqueue.

=cut

use parent qw(
  Cpanel::TaskProcessors::NotificationTasks::SubQueueBase
  Cpanel::TaskQueue::SubQueue::Adder
);

use Cpanel::Time::ISO ();
use Cpanel::TimeHiRes ();

use constant {
    _MAX_TRIES => 10,
};

=head1 METHODS

=head2 I<CLASS>->add( class => '..', KEY0 => VALUE0, .. )

This function stores the list of key/value pairs in the queue.
It determines a “name” for the queue entry internally then calls
the base class’s function of the same name.

Note that C<class> is a required value.

=cut

sub add {
    my ( $class, @args_array ) = @_;

    my $args_class = {@args_array}->{'class'} or do {
        die "No “class” given! (@args_array)";
    };

    for ( 1 .. _MAX_TRIES() ) {
        my ( $secs, $usecs ) = Cpanel::TimeHiRes::gettimeofday();

        #We might as well preserve lexical sorting ability
        #as best we might, though this doesn’t require that.
        my $name = join(
            q<_>,

            #Write ISO time for ease of debugging.
            Cpanel::Time::ISO::unix2iso($secs),

            #$usecs will always be less than 1 million (0xf4240).
            sprintf( '%05x', $usecs ),

            $args_class,
        );

        return 1 if $class->SUPER::add( $name => \@args_array );

        #We only get here if we failed to add, which means there was
        #a filesystem naming conflict. Since the names are determined
        #based on time, let’s sleep() for a bit and try again with a
        #different name.
        Cpanel::TimeHiRes::sleep(0.001);
    }

    die sprintf( "Failed %d times to add a notification subqueue item?? (@args_array)", _MAX_TRIES() );
}

1;
