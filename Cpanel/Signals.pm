package Cpanel::Signals;

# cpanel - Cpanel/Signals.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Signals - Keep track of signals and handle them when possible

=head1 SYNOPSIS

    use Cpanel::Signals ();

    local $SIG{'TERM'} = \&Cpanel::Signals::set_TERM;

    Cpanel::Signals::has_signal('TERM'); # will not clear TERM

    Cpanel::Signals::signal_needs_to_be_handled('TERM'); # will clear TERM

=cut

our $CURRENT_SIGNALS = 0;

our %SIGNAL_MAP = (
    'TERM' => 2,
    'USR1' => 4,
    'USR2' => 8,
);

=head2 set_USR1

This function is intended to be installed as the
handler for USR1

Example:
local $SIG{'USR1'} = \&Cpanel::Signals::set_USR1;

=cut

sub set_USR1 { return ( $CURRENT_SIGNALS |= 4 ); }    # Avoid the hash lookup in the unsafe perl 5.6 signal handler

=head2 set_TERM

This function is intended to be installed as the
handler for TERM

Example:
local $SIG{'TERM'} = \&Cpanel::Signals::set_TERM;

=cut

sub set_TERM { return ( $CURRENT_SIGNALS |= 2 ); }    # Avoid the hash lookup in the unsafe perl 5.6 signal handler

=head2 signal_needs_to_be_handled($signal)

Check to see if the the $signal has been recieved
and clear the state so the next check will
return false unless the signal is received again.

=cut

sub signal_needs_to_be_handled {
    my ($signal) = @_;

    if ( $CURRENT_SIGNALS & $SIGNAL_MAP{$signal} ) {
        $CURRENT_SIGNALS ^= $SIGNAL_MAP{$signal};
        return 1;
    }

    return 0;
}

=head2 has_signal($signal)

Check to see if the the $signal has been recieved.

This will not clear the state and the next check
will always return true.  If the caller is handling
the signal it should call signal_needs_to_be_handled()

=cut

sub has_signal {
    return ( $CURRENT_SIGNALS & $SIGNAL_MAP{ $_[0] } ) ? 1 : 0;
}

1;
