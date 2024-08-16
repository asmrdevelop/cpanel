package Cpanel::iContact::Class::Backup::PreBackupNotice;

# cpanel - Cpanel/iContact/Class/Backup/PreBackupNotice.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel::ConfigFiles ();

my @args = qw(origin);

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
        'script_name'            => $Cpanel::ConfigFiles::CPANEL_ROOT . '/scripts/precpbackup',
        'backup_conf_file'       => '/etc/cpbackup.conf',
        'backup_conf_modify_url' => $self->_get_backup_conf_modify_url(),
        map { $_ => $self->{'_opts'}{$_} } @args,
    );

    return %template_args;
}

sub _get_backup_conf_modify_url {
    my ($self) = @_;
    return $self->assemble_whm_url('scripts/backupset');
}

1;
