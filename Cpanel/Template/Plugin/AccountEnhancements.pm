package Cpanel::Template::Plugin::AccountEnhancements;

# cpanel - Cpanel/Template/Plugin/AccountEnhancements.pm
#                                                           Copyright 2022 cPanel, L.L.C.
#                                                                    All rights reserved.
# copyright@cpanel.net                                                  http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use cPstrict;
use Whostmgr::AccountEnhancements           ();
use Whostmgr::AccountEnhancements::Reseller ();

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::AccountEnhancements

=head1 DESCRIPTION

A TT plugin that exposes Account Enhancement logic for cPanel & WHM.

(NB: If any APIs materialize that expose this information, then prefer
those.)

=cut

use parent 'Template::Plugin';

=head1 METHODS

=head2 new

Constructor

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<SCALAR>

A new C<Cpanel::Template::Plugin::AccountEnhancements> object

=back

=back

=cut

sub new {
    return bless {}, $_[0];
}

=head2 list()

This calls
C<Whostmgr::AccountEnhancements::list()>
and returns a hash containing the enhancement list and any warnings.

=head3 RETURNS

Returns a hashref containing keys:

=over 1

=item data - an arrayref of enhancement objects

=item warnings - an arrayref of warning strings

=item errors - an arrayref of error strings

=back

=cut

sub list ($self) {
    my @errors;
    my ( $enhancements, $warnings ) = eval { Whostmgr::AccountEnhancements::list() };
    push @errors, $@ if $@;
    return {
        'data'     => $enhancements,
        'warnings' => $self->_format_exceptions($warnings),
        'errors'   => $self->_format_exceptions( \@errors )
    };
}

=head2 list_enhancement_limits()

This calls
C<Whostmgr::AccountEnhancements::Reseller::list_enhancement_limits()>
and returns a hash containing the enhancement list of unique ids and any warnings.

=head3 RETURNS

Returns a hashref containing keys:

=over 1

=item data - a hashref of enhancement limit objects, example: { enhancement_id => { limit: '15', limited: 1 } }

=item warnings - an arrayref of warning strings

=item errors - an arrayref of error strings

=back

=cut

sub list_enhancement_limits ( $self, $username ) {
    my @errors;
    my ( $enhancements, $warnings ) = eval { Whostmgr::AccountEnhancements::Reseller::list_enhancement_limits($username) };
    push @errors, $@ if $@;
    return {
        'data'     => $enhancements,
        'warnings' => $self->_format_exceptions($warnings),
        'errors'   => $self->_format_exceptions( \@errors )
    };
}

=head2 _format_exceptions($exceptions)

Turns an arrayref of error messages into UI ready errors.
If an element is an instance of C<Cpanel::Exception>, it will
return the error string without the id. Otherwise the exception is
left as-is.

=head3 ARGUMENTS

=over 1

=item $exceptions - ARRAYREF of exceptions as strings or C<Cpanel::Exception> objects

=back

=head3 RETURNS

An ARRAYREF of strings

=cut

sub _format_exceptions ( $self, $exceptions ) {

    my @result;
    if ( ref $exceptions eq 'ARRAY' ) {
        foreach my $exception ( @{$exceptions} ) {
            if ( eval { $exception->isa('Cpanel::Exception') } ) {
                $exception = $exception->to_string_no_id();
            }
            push @result, $exception;
        }
    }

    return \@result;
}

1;
