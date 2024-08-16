package Cpanel::iContact::Class::RPMVersions::Notify;

# cpanel - Cpanel/iContact/Class/RPMVersions/Notify.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel::ConfigFiles ();

my @required_args = qw(
  origin
  versions_directory
  local_keys
);

my @template_args = (@required_args);

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
        'update_local_rpm_versions_script_path' => $Cpanel::ConfigFiles::CPANEL_ROOT . '/scripts/update_local_rpm_versions',
        'cpupdate_conf_path'                    => '/etc/cpupdate.conf',
        map { $_ => $self->{'_opts'}{$_} } (@template_args)
    );
}

1;
