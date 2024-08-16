package Cpanel::iContact::Class::MailServer::OOM;

# cpanel - Cpanel/iContact/Class/MailServer/OOM.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw(
  account
  current_memory_limit
  service
);

my @optional_args = qw(
  mailbox_status
);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args,
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        'whm_mailserver_config_url' => $self->assemble_whm_url('scripts2/mailserversetup'),
        map { $_ => $self->{'_opts'}{$_} } ( @required_args, @optional_args )

    );
}

1;
