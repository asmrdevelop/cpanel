package Cpanel::SignalManager;

# cpanel - Cpanel/SignalManager.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::SignalManager - Easy manipulation of multiple handlers per signal.

=head1 SYNOPSIS

    my $sigman = Cpanel::SignalManager->new();

    #Register a signal handler. This is functionally equivalent
    #to just setting $SIG{'INT'}. (i.e., will override the default signal behavior)
    my $random_name = $sigman->push( signal => 'INT', handler => sub { .. } );

    #...or, do it by explicitly naming the handler. This will register
    #a second handler that will run immediately after the first.
    $sigman->push( name => 'my_handler', signal => 'INT', handler => sub { .. } );

    #NB: The order of execution of the handlers
    #is guaranteed to be “my_handler”, then $random_name.

    #By default, this object’s handlers will prevent the default signal action.
    #The command below will make the object execute Perl’s default action in
    #response to the signal, AFTER executing the handler stack.
    $sigman->enable_signal_resend( signal => 'INT' );

    #Delete handlers from the queue by name:
    my $handler2 = $sigman->delete( name => 'my_handler', signal => 'INT' );

    #Note the FATAL_SIGNALS() courtesy method:
    $sigman->push( signal => $_, handler => sub { .. } ) for $sigman->FATAL_SIGNALS();

    #This will restore the signal handlers that were in place when the object was created.
    #!!! BUT see below about non-Perl signal handlers!
    undef $sigman;

=head1 DESCRIPTION

This module is a shim around Perl’s native signal handling that facilitates
storing multiple handlers per signal. Each handler is executed in reverse order
from that in which it was added: last-in-first-out.

Uncaught exceptions are stored, then rethrown after the handlers for a
given queue are done. Multiple exceptions are thrown in a
C<Cpanel::Exception::Collection> object.

You can also set signals to be “resent”, which facilitates useful things
like C<unlink()>ing a touch file before a process ends via signal.
This is better than simply C<exit()>ing because whoever is watching the
signaled process will then see what actually prompted the termination.

When the C<Cpanel::SignalManager> object is destroyed, the original signal
handlers are restored. NOTE, however, that because the perl interpreter
inherits signal handlers from whatever C<exec()>ed it, and because XS code can
set signal handlers in C, it is possible for this not to work very well.
(It was considered, but decided against, to set all signal handlers to
'DEFAULT' on object destruction instead.)

This class depends on Perl’s global C<%SIG> hash to do its work.
It is recommended that each process have at most one instance of this class.

=cut

#----------------------------------------------------------------------

use strict;

use Try::Tiny;

use Cpanel::Exception ();

our $DEBUG;

sub FATAL_SIGNALS {
    return (
        'ABRT',
        'ALRM',
        'BUS',

        #'FPE',      #Perl actually prevents this from happening

        'HUP',
        'ILL',
        'INT',
        'PIPE',
        'POLL',
        'QUIT',
        'SEGV',    #Perl should never segfault, but ...
        'SYS',
        'TERM',
        'TRAP',
        'USR1',
        'USR2',
        'VTALRM',
        'XCPU',
        'XFSZ',
    );
}

#Accepts no arguments
sub new {
    my ($class) = @_;

    my $self = {
        _orig_pid => $$,
    };

    if ($DEBUG) {
        $self->{'_created'} = [ map { [ caller($_) ] } ( 1 .. 6 ) ];
    }

    return bless $self, $class;
}

#Named arguments:
#
#   signal      required, string
#   handler     required, coderef
#   name        optional, string (generated if not given)
#
#Returns the name of the new handler.
#
sub push {
    my ( $self, %opts ) = @_;

    my $handlers_ar = $self->{"_$opts{'signal'}"};

    my $index = $handlers_ar ? @$handlers_ar : 0;

    return $self->_add_handler( %opts, index => $index );
}

#Named arguments:
#
#   signal      required, string
#   name        required, string
#
sub delete {
    my ( $self, %opts ) = @_;

    my ( $signal, $name ) = @opts{qw( signal  name )};

    $self->_validate_signal($signal);

    my $handlers_ar = $self->{"_$signal"};

    if ($handlers_ar) {
        for my $i ( 0 .. $#$handlers_ar ) {
            if ( $handlers_ar->[$i][0] eq $name ) {
                if ( scalar(@$handlers_ar) == 1 ) {
                    $SIG{$signal} = delete $self->{'_former_SIG'}{$signal};
                }

                return splice( @$handlers_ar, $i, 1 )->[1];
            }
        }
    }

    die "The “$signal” signal has no handler named “$name”!";
}

#Named arguments:
#
#   signal      required, string
#
#NOTE: This accepts only a “fatal” signal,
#so would throw if passed e.g., CHLD.
sub enable_signal_resend {
    my ( $self, %opts ) = @_;

    $self->_must_be_fatal_signal( $opts{'signal'} );

    return $self->_set_signal_resend( $opts{'signal'}, 1 );
}

#Named arguments:
#
#   signal      required, string
#
#Only accepts fatal.
sub disable_signal_resend {
    my ( $self, %opts ) = @_;

    $self->_must_be_fatal_signal( $opts{'signal'} );

    return $self->_set_signal_resend( $opts{'signal'}, 0 );
}

#----------------------------------------------------------------------

sub _set_signal_resend {
    my ( $self, $signal, $resend_yn ) = @_;

    $self->_validate_signal($signal);

    $self->{'_signal_resend'}{$signal} = $resend_yn;

    return 1;
}

sub _name_exists_for_signal {
    my ( $self, $name, $signal ) = @_;

    if ( $self->{"_$signal"} ) {
        for my $i ( @{ $self->{"_$signal"} } ) {
            return 1 if $i->[0] eq $name;
        }
    }

    return 0;
}

sub _add_handler {
    my ( $self, %opts ) = @_;

    my ( $signal, $handler_cr, $name, $index ) = @opts{qw(signal handler name index)};

    $self->_validate_signal($signal);

    if ( defined $name ) {
        if ( $self->_name_exists_for_signal( $name, $signal ) ) {
            die "The “$signal” signal already has a handler named “$name”!";
        }
    }
    else {
        do {
            $name = caller . '-' . rand;
        } while ( $self->_name_exists_for_signal( $name, $signal ) );
    }

    $self->_ensure_generic_handler($signal);

    splice( @{ $self->{"_$signal"} }, $index, 0, [ $name => $handler_cr ] );

    return $name;
}

sub _validate_signal {
    my ( $self, $signal ) = @_;

    die "“$signal” is not the name if a valid signal on this system!" if !exists $SIG{$signal};

    return 1;
}

sub DESTROY {
    my ($self) = @_;

    my $frmr_hr = $self->{'_former_SIG'};
    return if !$frmr_hr;    #nothing to restore

    $SIG{$_} = $frmr_hr->{$_} for keys %$frmr_hr;

    return;
}

sub _must_be_fatal_signal {
    my ( $self, $signal ) = @_;

    for ( $self->FATAL_SIGNALS() ) {
        return 1 if $signal eq $_;
    }

    die "“$signal” is not a fatal signal.";
}

sub _ensure_generic_handler {
    my ( $self, $signal ) = @_;

    if ( !$self->{"_$signal"} ) {
        $self->{'_former_SIG'}{$signal} = $SIG{$signal};

        my $handlers_ar = [];

        $self->{"_$signal"} = $handlers_ar;

        my $resend_hr = $self->{'_signal_resend'} ||= {};

        #NOTE: It is important that there be no
        #direct references to $self in here; otherwise,
        #“dangling” references will prevent $self from
        #being DESTROYed when it would otherwise be.
        #
        $SIG{$signal} = sub {
            my ($sig) = @_;

            my @caught;

            for my $todo_cr ( reverse @$handlers_ar ) {
                try {
                    $todo_cr->[1]->($sig);
                }
                catch {
                    CORE::push( @caught, $_ );
                };
            }

            if ( $resend_hr->{$sig} ) {
                $SIG{$sig} = 'DEFAULT';
                kill $sig, $$;
            }

            if (@caught) {
                if ( @caught == 1 ) {
                    die $caught[0];
                }

                die Cpanel::Exception::create( 'Collection', [ exceptions => \@caught ] );
            }
        };
    }

    return;
}

1;
