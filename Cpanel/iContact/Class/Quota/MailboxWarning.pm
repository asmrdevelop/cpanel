package Cpanel::iContact::Class::Quota::MailboxWarning;

# cpanel - Cpanel/iContact/Class/Quota/MailboxWarning.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw(
  box
  status
  diskused
  disklimit
  percentused
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
        'manage_disk_usage_url' => $self->assemble_webmail_url('?goto_app=Email_DiskUsage'),
        map { $_ => $self->{'_opts'}{$_} } ( @required_args, 'adjusturl' )
    );
}

1;
