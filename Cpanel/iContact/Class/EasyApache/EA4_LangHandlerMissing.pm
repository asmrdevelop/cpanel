package Cpanel::iContact::Class::EasyApache::EA4_LangHandlerMissing;

# cpanel - Cpanel/iContact/Class/EasyApache/EA4_LangHandlerMissing.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=head1 NAME

Cpanel::iContact::Class::EasyApache::EA4_LangHandlerMissing

=head1 DESCRIPTION

This notification should be used when the EA4 subsystem finds a configuration
where the administrator setup a web server handler for a package.  However,
the handler is no longer installed.

Notifications like this are useful when running in the background or via YUM
hooks where the user is probably not paying attention to the screen output.

For example, the administrator used YUM to remove the suphp Apache handler
while it's currently configured for one the PHP packages.

=cut

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @args = qw(package language webserver missing_handler replacement_handler);

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
