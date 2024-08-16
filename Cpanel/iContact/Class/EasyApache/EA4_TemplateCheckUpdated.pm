package Cpanel::iContact::Class::EasyApache::EA4_TemplateCheckUpdated;

# cpanel - Cpanel/iContact/Class/EasyApache/EA4_TemplateCheckUpdated.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=head1 NAME

Cpanel::iContact::Class::EasyApache::EA4_TemplateCheckUpdated

=head1 DESCRIPTION

This notification should be used when the there are any changes made in the EA4 apache
environment that affects in updating existing templates in /var/cpanel/templates area.

Notifications like this are useful when the users have their local template copy setup for
any of the cPanel maintained templates so that they are informed of the changes and are
provided a chance to update their local copies.

The caller for this iContact notification will be from a hook script inside ea-apache24-config rpm.

=cut

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @args = qw( templates first_time );

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @args,
    );
}

sub _template_args {
    my ($self) = @_;

    my %template_args = (
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } @args
    );

    return %template_args;
}

1;
