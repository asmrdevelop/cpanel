package Cpanel::iContact::Class::SSL::CheckAllCertsWarnings;

# cpanel - Cpanel/iContact/Class/SSL/CheckAllCertsWarnings.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::SSL::CheckAllCertsWarnings - Module for notifying if the checkallsslcerts script has any warnings.

=head1 SYNOPSIS

 Cpanel::iContact::Class::SSL::CheckAllCertsWarnings->new(
        origin   => '/usr/local/cpanel/bin/checkallsslcerts',
        warnings => $warnings,
 );

=head1 DESCRIPTION

Module for notifying if the checkallsslcerts script has any warnings.

=cut

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = ( 'origin', 'warnings' );

sub _required_args {
    my ($class) = @_;

    return @required_args;
}

sub _icontact_args {
    my ($self) = @_;

    my @args = (
        $self->SUPER::_icontact_args(),

        from => 'cPanel Service SSL Certificate Warnings',
    );

    return @args;
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        map { $_ => $self->{'_opts'}{$_} } @required_args,
    );
}

1;
