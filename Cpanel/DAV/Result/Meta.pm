package Cpanel::DAV::Result::Meta;

# cpanel - Cpanel/DAV/Result/Meta.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Carp ();
use Class::Accessor 'antlers';    # lightweight Moose-style attributes

=head1 NAME

Cpanel::DAV::Result:Meta

=head1 DESCRIPTION

This module contains the definition of a Meta object used to collection

=cut

my %validators;

sub new {
    my ($class) = @_;
    my $self = {
        ok           => 1,
        is_exception => 0,
        no_response  => 0,
        status       => 0,
        text         => '',
        details      => undef,
        path         => '',
        etag         => '',
    };
    bless $self, $class;
    return $self;
}

=head1 ATTRIBUTES

The attributes of a result->meta are accessible by getter/setter methods
of the same name as the attribute.

=head2 ok

Truthy if the request was handled by back end. Falsy otherwise. By default its truthy.

=cut

has ok => ( is => 'rw' );

=head2 is_exception

Truthy if the request threw an exception. The exception details should be located in the
details attribute. Falsey otherwise.

=cut

has is_exception => ( is => 'rw' );

=head2 no_response

Truthy if the request did not return data. Falsey otherwise.

=cut

has no_response => ( is => 'rw' );

=head2 text

Message generated to correspond with an error. Empty otherwise.

=cut

has text => ( is => 'rw', isa => 'Str' );

=head2 status

Status code returned by the backend if applicable.

=cut

has status => ( is => 'rw', isa => 'Int' );
$validators{status} = sub { return shift() =~ /^[0-9]+$/ };

=head2 details

Any specific data related to a failure. May be an exception ref if is_exception is truthy,
otherwise it may be any other data type or collection related to the failure.

=cut

has details => ( is => 'rw' );

=head2 path

Optional path for the resource effected by the operation.

=cut

has path => ( is => 'rw', isa => 'Str' );

=head2 etag

Optional etag for the resource effected by the operation.

=cut

has etag => ( is => 'rw', isa => 'Str' );

###################################################

sub set {
    my ( $self, $key, $value ) = @_;
    if ( 'CODE' eq ref $validators{$key} && !$validators{$key}->($value) ) {

        # Don't make this fatal (yet?), but leave the field empty and cluck angrily about it. Hopefully someone will notice.
        Carp::cluck(qq{The following value did not meet the validation criteria for “$key”: $value});
        return;
    }
    return $self->{$key} = $value;
}

sub TO_JSON {
    return { %{ $_[0] } };
}

1;
