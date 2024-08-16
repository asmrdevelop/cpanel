package Cpanel::iContact::Class::appconfig::Notify;

# cpanel - Cpanel/iContact/Class/appconfig/Notify.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @required_args = qw(
  service
  name
);

my @template_args = (
    @required_args,
    qw(
      acls
      features
      user
      url
      phpConfig
      displayname
      entryurl
    )
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

    my $system_info_args = $self->_get_system_info_template_vars();
    return (
        $self->SUPER::_template_args(),
        %{$system_info_args},
        'get_appconfig_application_list_url' => $self->_get_appconfig_application_list_url($system_info_args),
        map { $_ => $self->{'_opts'}{$_} } (@template_args)
    );
}

sub _icontact_args {
    my ($self) = @_;

    my @args = (
        $self->SUPER::_icontact_args(),

        #TODO: Give customers control over this string.
        from => 'cPanel AppConfig',
    );

    return @args;
}

sub _get_appconfig_application_list_url {
    my ($self) = @_;
    return $self->assemble_whm_url('scripts6/get_appconfig_application_list');
}

1;
