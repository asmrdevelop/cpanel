package Cpanel::iContact::Class::Check::EximConfig;

# cpanel - Cpanel/iContact/Class/Check/EximConfig.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel::ConfigFiles ();

my @args = qw(
  is_whm
  application
  source_ip_address
  origin
  cpanel_version
  previous_config_version
  current_config_version
  new_config_version
  action
);

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
        'exim_acls_dir'            => $Cpanel::ConfigFiles::CPANEL_ROOT . '/etc/exim/acls/',
        'exim_conf_localopts_path' => '/etc/exim.conf.localopts',
        'whm_login_url'            => $self->_get_whm_login_url(),
        'exim_config_manager_url'  => $self->_get_exim_config_manager_url(),
        'cf_and_replacecf_paths'   => [ "$Cpanel::ConfigFiles::CPANEL_ROOT/etc/exim/cf", "$Cpanel::ConfigFiles::CPANEL_ROOT/etc/exim/replacecf" ],
        map { $_ => $self->{'_opts'}{$_} } ( 'exim_backup_path', 'docs_url', @args ),
    );

    return %template_args;
}

sub _get_whm_login_url {
    my ($self) = @_;
    return $self->assemble_whm_url('');
}

sub _get_exim_config_manager_url {
    my ($self) = @_;
    return $self->assemble_whm_url('scripts2/displayeximconfforedit');
}

1;
