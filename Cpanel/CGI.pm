package Cpanel::CGI;

# cpanel - Cpanel/CGI.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::CGI

=head1 SYNOPSIS

    use parent qw( Cpanel::CGI );

    __PACKAGE__->new()->run() if !caller;

    sub _do_initial {
        my ($self) = @_;

        my $thing = $self->get_param('thing');
        my @things = $self->get_param('things');

        #Print HTTP headers, as described in parent class …
    }

    #Optional
    sub _do_interactive { ... }

=head1 DESCRIPTION

This thin framework for a CGI application augments L<Cpanel::CGI::NoForm>
with form processing.

=head1 PROVIDED METHODS

=cut

use strict;
use warnings;

use parent 'Cpanel::CGI::NoForm';

use Cpanel::Context     ();
use Cpanel::Form        ();
use Cpanel::Form::Param ();

=head2 I<CLASS>->new()

Parses form parameters from C<$ENV{'QUERY_STRING'}> and the message body
and returns an instantiated object.

=cut

sub new {
    my ($class) = @_;

    my $formref_hr = Cpanel::Form::parseform();

    my $self = $class->SUPER::new(@_);
    $self->{'_form'} = Cpanel::Form::Param->new( { parseform_hr => $formref_hr } );

    return $self;
}

=head2 $val = I<OBJ>->get_param( NAME )

Returns a single value for the given NAME.

=cut

sub get_param {
    my ( $self, $name ) = @_;

    return scalar $self->{'_form'}->param($name);
}

=head2 @vals = I<OBJ>->get_params( NAME )

Returns 0 or more values for the given NAME.

=cut

sub get_params {
    my ( $self, $name ) = @_;

    Cpanel::Context::must_be_list();

    return $self->{'_form'}->param($name);
}

1;
