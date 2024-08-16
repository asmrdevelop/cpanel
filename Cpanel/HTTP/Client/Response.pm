package Cpanel::HTTP::Client::Response;

# cpanel - Cpanel/HTTP/Client/Response.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=pod

=encoding utf-8

=head1 NAME

Cpanel::HTTP::Client::Response - C<Cpanel::HTTP::Client> responses

=head1 DESCRIPTION

This is only here to provide a C<redirects()> method until
C<HTTP::Tiny::UA::Response> provides it.

=cut

use parent 'HTTP::Tiny::UA::Response';

sub new {
    my ( $class, $opts_hr, @extra ) = @_;

    my $self = $class->SUPER::new( $opts_hr, @extra );

    #We have to store this ourselves; the base class has an
    #internal white-list of properties.
    $self->{'_cp_redirects'} = $opts_hr->{'redirects'};

    return $self;
}

sub redirects {
    my ($self) = @_;

    return [ map { ( ref $self )->new($_) } @{ $self->{'_cp_redirects'} } ];
}

sub TO_JSON {
    my $json = { %{ $_[0] } };

    # let's make this key a little more readable *AND* make the object be able to reconstitute
    # from the hashref produced by this function
    $json->{redirects} = delete $json->{_cp_redirects};

    return $json;
}

1;
