package Cpanel::Admin::Base::ExposeExceptionsUNSAFE;

# cpanel - Cpanel/Admin/Base/ExposeExceptionsUNSAFE.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#----------------------------------------------------------------------

=encoding utf-8

=head1 NAME

Cpanel::Admin::Base::ExposeExceptionsUNSAFE

=head1 DESCRIPTION

This module facilitates composition of admin functions that pass
all untrapped exceptions back to the user.

In general, this is a bad idea. It’s fundamentally an information disclosure
flaw. This logic is only here to facilitate moving the admin modules that
began life as “Call”-type admin binaries to the C<Cpanel::Admin::Modules::*>
namespace. Those modules’ functions should ideally be migrated to the
approach described in L<Cpanel::Admin::Base>, and this module should be
deleted—or maybe kept around as an example of what not to do. :-P

=cut

#----------------------------------------------------------------------

use Try::Tiny;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 handle_untrapped_exception( $ERROR )

Overrides the base class’s method of the same name.
Returns $ERROR’s Cpanel::Exception ID (if any), class, and stringified form.
This is the information that the user process will receive about $ERROR.

=cut

sub handle_untrapped_exception {
    my ($err) = @_;

    my $class = ref $err || undef;

    my ( $err_id, $err_string );

    if ( try { $err->isa('Cpanel::Exception') } ) {
        ( $err_id, $err_string ) = ( $err->id(), $err->to_locale_string_no_id() );
    }
    else {
        ( $err_id, $err_string ) = ( undef, "$err" );
    }

    return ( $err_id, $class, $err_string );
}

1;
