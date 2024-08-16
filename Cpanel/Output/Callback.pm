package Cpanel::Output::Callback;

# cpanel - Cpanel/Output/Callback.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Output::Callback

=head1 SYNOPSIS

    my $output = Cpanel::Output::Callback->new(
        on_render => sub ($msg_hr) { ... },
    );

=head1 DESCRIPTION

This module subclasses L<Cpanel::Output> but overrides its
behavior of outputting JSON such that instead the output is to
a callback, called C<on_render> in the constructor.

C<on_render> receives a hashref as parameter; for details of that
hashref’s contents see L<Cpanel::Output>. (The most important pieces
are C<type>, C<contents>, and C<indent>.)

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Output );

#----------------------------------------------------------------------

sub _init ( $self, $opts_hr ) {
    $self->{'_on_render'} = $opts_hr->{'on_render'} or do {
        die 'need “on_render”!';
    };

    return;
}

sub _RENDER ( $self, $msg_hr ) {
    $self->{'_on_render'}->($msg_hr);

    return;
}

1;
