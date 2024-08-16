package Cpanel::iContact::Class::AdminBin::FullBackup;

# cpanel - Cpanel/iContact/Class/AdminBin/FullBackup.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @required_args = qw(pkgfile backupdest user user_domain);

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
        'backup_url' => $self->assemble_cpanel_url('?goto_app=Backups_Home'),
        map { $_ => $self->{'_opts'}{$_} } (
            @required_args, qw(
              pkgdir
              username
              ftpserver
              ftpuser
              attach_files
              errors
            )
        )
    );
}

1;
