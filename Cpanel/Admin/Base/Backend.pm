package Cpanel::Admin::Base::Backend;

# cpanel - Cpanel/Admin/Base/Backend.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Admin::Base::Backend

=head1 DESCRIPTION

This module defines interfaces for pieces of L<Cpanel::Admin::Base>’s logic
to facilitate testing.

Please do not reuse this module outside of Cpanel::Admin::Base! Instead,
refactor the logic that interests you, and call that module from this one.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 process_exception_whitelist( $ERR, \%ON_EXCEPTION )

This implements the “whitelist” behavior that L<Cpanel::Admin::Base>’s
documentation describes. $ERR is the exception that was thrown,
and %ON_EXCEPTION is a hash of ( class => handler ).

If the exception matches the whitelist, it will be converted into the
appropriate L<Cpanel::Exception::AdminError>, which will be thrown.

Otherwise, nothing is returned … after which, presumably, the caller
will rethrow $ERR.

=cut

sub process_exception_whitelist {
    my ( $err, $on_exception_hr ) = @_;

    my @classes = keys %$on_exception_hr;

    for my $class ( sort { length($b) <=> length($a) } @classes ) {
        if ( $err->isa($class) ) {
            my @admin_err_args;

            if ( my $handler_cr = $on_exception_hr->{$class} ) {
                @admin_err_args = $handler_cr->($err);
            }
            else {
                my ( $msg, $metadata );

                if ( $err->isa('Cpanel::Exception') ) {
                    $msg      = $err->to_locale_string_no_id();
                    $metadata = $err->get_all_metadata();
                }
                else {
                    $msg = "$err";
                }

                @admin_err_args = (
                    class    => ref($err),
                    message  => $msg,
                    metadata => $metadata,
                );
            }

            if (@admin_err_args) {
                my $user_err = Cpanel::Exception::create(
                    'AdminError',
                    \@admin_err_args,
                );

                if ( $err->isa('Cpanel::Exception') ) {
                    $user_err->set_id( $err->id() );
                }

                die $user_err;
            }
        }
    }

    return;
}

1;
