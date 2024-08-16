package Cpanel::AttributeProvider;

# cpanel - Cpanel/AttributeProvider.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Context ();

my $ATTRS_KEY = '_' . __PACKAGE__ . '_attrs';

=encoding utf-8

=head1 NAME

Cpanel::AttributeProvider

=head1 SYNOPSIS

    package My::Class;

    use parent 'Cpanel::AttributeProvider';

    package main;

    my $obj = My::Class->new();
    $obj->import_attrs( { foo => 1, bar => 2 } );

    $obj->get_attr('foo');  # 1
    $obj->get_attr('bar');  # 2

    $obj->attr_exists('qux');   # falsey
    $obj->get_attr('qux');      # undef

    $obj->set_attr('qux', 5);
    @names = $obj->get_attr_names();    # foo, bar, qux

    $obj->delete_attr('qux');

=head1 DESCRIPTION

Yet another accessor base class. This one adheres to the notion that
method names should be verbs. YMMV.

=cut

sub new {
    my ( $class, %self ) = @_;

    $self{$ATTRS_KEY} = {};

    return bless \%self, $class;
}

sub import_attrs {
    my ( $self, $attrs_hr ) = @_;

    die 'Must be a hashref!' if 'HASH' ne ref $attrs_hr;

    @{ $self->{$ATTRS_KEY} }{ keys %$attrs_hr } = values %$attrs_hr;

    return;
}

sub get_attr_names {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    return keys %{ $self->{$ATTRS_KEY} };
}

sub set_attr {
    my ( $self, $param, $value ) = @_;

    die 'Must give a value!' if @_ < 3;

    die 'Must give a param!' if !defined $param;

    return $self->{$ATTRS_KEY}{$param} = $value;
}

sub get_attr {
    my ( $self, $param ) = @_;

    die 'Must give a param!' if !defined $param;

    return $self->{$ATTRS_KEY}{$param};
}

sub get_attrs {
    my ($self) = @_;

    return $self->{$ATTRS_KEY};
}

sub delete_attr {
    my ( $self, $param ) = @_;

    die 'Must give a param!' if !defined $param;

    return delete $self->{$ATTRS_KEY}{$param};
}

sub attr_exists {
    my ( $self, $param ) = @_;

    die 'Must give a param!' if !defined $param;

    return exists $self->{$ATTRS_KEY}{$param} ? 1 : 0;
}

1;
