package Cpanel::iContact::Class::Check::ImmutableFiles;

# cpanel - Cpanel/iContact/Class/Check/ImmutableFiles.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

use Cpanel::ConfigFiles ();

my @args = qw(chattr_command);

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

        'upcp_path'                            => $Cpanel::ConfigFiles::CPANEL_ROOT . '/scripts/upcp',
        'upcp_sync_command'                    => $Cpanel::ConfigFiles::CPANEL_ROOT . '/scripts/upcp --sync',
        'cpanelsync_exclude_file'              => '/etc/cpanelsync.exclude',
        'cpanel_root'                          => $Cpanel::ConfigFiles::CPANEL_ROOT,
        'cpanelsync_exclude_documentation_url' => 'https://go.cpanel.net/syncexclude',

        map { $_ => $self->{'_opts'}{$_} } (@args),
    );

    return %template_args;
}

1;
