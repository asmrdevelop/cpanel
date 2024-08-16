package Cpanel::Try;

# cpanel - Cpanel/Try.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Try - exception-class-specific “catch” blocks.

=head1 SYNOPSIS

    $result = Cpanel::Try::try(
        sub { .. },

        'Exception::Class::A' => $handler_a,
        'Exception::Class::B' => $handler_b,

        q<> => $handler_default,

        $finally_cr,
    );

=head1 DESCRIPTION

L<Try::Tiny> is great, but implementing type-specific “catch” blocks
with it—a standard feature of many languages’ exception handling—is
a bit clumsy.

This module attempts to rectify that by providing a quick and easy
way to indicate “catch” blocks for specific exception cases. We also
implement Try::Tiny’s protection of C<$@> and optional “finally”
behavior.

=head1 !!! BEFORE YOU EXTEND THIS MODULE !!!

This module is intended to be as lightweight as possible. The more
logic is added here, the less usable this becomes in
memory-constrained contexts like servers. B<Please> do not extend this
module without weighing whether there is an acceptable way to do what
you want with the existsing functionality.

=head1 FUNCTIONS

=head2 try( $TODO_CR, @CATCHERS_KV, [ $FINALLY_CR ] )

Executes $TODO_CR in the same calling context (i.e., list, scalar, or void)
as C<try()>.

If $TODO_CR succeeds, then $FINALLY_CR, if given, is
executed, and the result of $TODO_CR is returned.

If $TODO_CR fails (i.e., throws an exception), then we iterate
through @CATCHERS_KV (in the given order) in search of a handler
for the exception.

If no such handler is found, then $FINALLY_CR, if given, is run,
with C<$@> set to the thrown exception beforehand. Then the exception
is rethrown.

B<NOTE:> This is an important difference between this module
and L<Try::Tiny>: whereas Try::Tiny will ignore an exception if no
C<catch> block is given, this module will rethrow the exception.

B<NOTE:> Another important difference from L<Try::Tiny> is that this
module does B<NOT> set C<$_> within a handler, but sets C<$@> instead.
This makes it much simpler to get Perl’s useful special behaviors for
plain C<warn()> and C<die()>.

If, on the other hand, a suitable exception handler is found, then:

=over

=item * We execute the handler. C<$@> is set to the thrown exception
beforehand, so plain C<warn()> and C<die()> within the handler will
implement their respective “special” behaviors.

The C<$@> value is also, as a convenience, given as a parameter to
the handler.

(NB: Unlike in C<Try::Tiny>, C<$_> is NOT set!)

=item * $FINALLY_CR, if given, is run (with C<$@> set and passed as a
parameter).

=item * We return empty/undef to the caller.

=back

=head3 Exception handler matching

@CATCHERS_KV is a list of key-value pairs. For now, keys are
matched to exceptions according to the following logic, in the
order given:

=over

=item * If the key is an empty string, the handler matches
(regardless of what the actual exception is). This is a “default”
handler.

=item * If the exception C<isa()> the key, the handler matches.

=back

There are other potential possibilities like allowing keys to be
regexps or coderefs, but for now this gets us “off the ground”.

=head3 Examples

Make exceptions nonfatal but still C<warn()>:

    Cpanel::Try::try(
        sub { .. },
        q<> => sub { warn },
    );

Similar to ordinary try/catch (but remember that C<$@>, not C<$_>,
is populated):

    Cpanel::Try::try(
        sub { .. },
        q<> => sub {
            {
                my $err = $@;

                local $@;
                log_error($err);
            }

            die;
        },
    );

Allow exceptions to propagate but also have a “finally” block:

    Cpanel::Try::try(
        sub { .. },
        $finally_cr,
    );

Similar to try/catch/finally:

    Cpanel::Try::try(
        sub { .. },
        q<> => $catch_handler_cr,
        $finally_cr,
    );

A class-specific catcher that takes advantage of C<isa()>’s
acceptance of inheritance:

    Cpanel::Try::try (
        \&do_stuff,

        'Cpanel::Exception::IO::FileOpenError' => \&handle_open_error,

        'Cpanel::Exception::IOError' => \&handle_any_other_IO_error,

        'Cpanel::Exception'  => \&handle_any_cpanel_exception,

        q<> => \&handle_generic_die,
    );

=cut

our $_DEFAULT_DOLLAR_AT = q<>;

our $_finally_cr;

sub try {    ## no critic qw( RequireArgUnpacking )
    my $todo_cr = shift;

    local $@;

    my ( $ok, $resp );

    local $_finally_cr = ( @_ % 2 ) ? pop : undef;

    if (wantarray) {
        $ok = eval { $resp = [ $todo_cr->() ]; 1 };
    }
    elsif ( defined wantarray ) {
        $ok = eval { $resp = $todo_cr->(); 1 };
    }
    else {
        $ok = eval { $todo_cr->(); 1 };
    }

    if ( !$ok ) {
        my $err = $@;

        my ( $rethrow_yn, $catch_err );

        while (@_) {
            if ( ( $_[0] eq q<> ) || eval { $err->isa( $_[0] ) } ) {

                $rethrow_yn = !eval {
                    $@ = $err;    ## no critic qw(RequireLocalizedPunctuationVars)

                    $_[1]->($err);

                    1;
                };

                $catch_err = $@;

                last;
            }

            splice @_, 0, 2;
        }

        if ($_finally_cr) {
            local $@;
            eval { $@ = $err; $_finally_cr->($err); 1 } or warn;    ## no critic qw(RequireLocalizedPunctuationVars)
        }

        die $catch_err if $rethrow_yn;

        return if @_;

        $@ = $err;    ## no critic qw(RequireLocalizedPunctuationVars)
        die;
    }

    if ($_finally_cr) {
        eval { $_finally_cr->($_DEFAULT_DOLLAR_AT); 1 } or warn;
    }

    return wantarray ? @$resp : $resp;
}

1;
