package Cpanel::Exception::ProcessFailed::Timeout;

# cpanel - Cpanel/Exception/ProcessFailed/Timeout.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#

=head1 NAME

Cpanel::Exception::ProcessFailed::Timeout

=head1 DESCRIPTION

Thrown from C<Cpanel::SafeRun::Object::new_or_die()> or similar code when
a child process being run is terminated by the parent when the child
exceeds a timeout, since other exceptions do not allow differentiation
between this case and that of a termination signal internal to the child or
external to both child and parent.

=head1 SYNOPSIS

  use Cpanel::Exception;

  ...

    if ($self->timed_out()) {
        die Cpanel::Exception::create(
            'ProcessFailed::Timeout',
            [
                process_name => $command,  # Optional
                pid          => $pid,      # Optional
                timeout      => $timeout   # Required, number > 0
            ],
        );
    }

=cut

use strict;
use warnings;

# Should Cpanel::Exception::Timeout be a parent too?
use parent qw( Cpanel::Exception::ProcessFailed );

use Cpanel::LocaleString ();

#metadata parameters:
#   timeout         (required, number)
#   process_name    (optional)
#   pid             (optional)
#
sub _default_phrase {
    my ($self) = @_;

    my ( $timeout, $name, $pid ) = map { $self->get($_) } qw(
      timeout
      process_name
      pid
    );

    die "Need “timeout”!"               if !defined($timeout);
    die "“timeout” cannot be negative!" if $timeout < 0;

    if ( length $name ) {
        if ( length $pid ) {
            return Cpanel::LocaleString->new(
                'The system aborted the subprocess “[_1]” (process [asis,ID] “[_2]”) because it reached the timeout of [quant,_3,second,seconds].',
                $name,
                $pid,
                $timeout
            );
        }
        else {
            return Cpanel::LocaleString->new(
                'The system aborted the subprocess “[_1]” because it reached the timeout of [quant,_2,second,seconds].',
                $name,
                $timeout
            );
        }
    }
    else {
        if ( length $pid ) {
            return Cpanel::LocaleString->new(
                'The system aborted the subprocess with the [asis,ID] “[_1]” because it reached the timeout of [quant,_2,second,seconds].',
                $pid,
                $timeout
            );
        }
        else {
            return Cpanel::LocaleString->new(
                'The system aborted the subprocess because it reached the timeout of [quant,_1,second,seconds].',
                $timeout
            );
        }
    }
}

1;
