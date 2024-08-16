package Cpanel::iContact::Class::Solr::Maintenance;

# cpanel - Cpanel/iContact/Class/Solr/Maintenance.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::Solr::Maintenance - Module for notifying if the dovecot solr maintenance script failed.

=head1 SYNOPSIS

 Cpanel::iContact::Class::Solr::Maintenance->new(
        origin   => '/usr/local/cpanel/3rdparty/scripts/cpanel_dovecot_solr_maintenance',
        actions => { task => $error_str },
 );

=head1 DESCRIPTION

Module for notifying if the dovecot solr maintenance script fails.

=cut

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = ( 'origin', 'actions' );

sub _required_args {
    my ($class) = @_;

    return @required_args;
}

sub _icontact_args {
    my ($self) = @_;

    my @args = (
        $self->SUPER::_icontact_args(),

        from => 'cPanel Dovecot Solr Maintenance',
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
