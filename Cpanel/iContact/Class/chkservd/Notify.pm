package Cpanel::iContact::Class::chkservd::Notify;

# cpanel - Cpanel/iContact/Class/chkservd/Notify.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::chkservd
);

use Cpanel::iContact::Utils ();

sub _TEMPLATE_ARGS_LIST {
    my ($self) = @_;

    return (
        $self->SUPER::_TEMPLATE_ARGS_LIST(),
        'service_status',
        'service_name',
    );
}

sub _OPTIONAL_TEMPLATE_ARGS_LIST {
    my ($self) = @_;

    return (
        'what_failed',
        'port',
        'command_error',
        'socket_error',
        'restart_count',
        'restart_info',
        'startup_log',
        'syslog_messages',
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        'service_manager_url'                         => $self->assemble_whm_url('scripts/srvmng#service-chkservd'),
        'tweaksettings_chkservd_url'                  => $self->assemble_whm_url('scripts2/tweaksettings?find=chkservd'),
        'tweaksettings_chkservd_plaintext_notify_url' => $self->assemble_whm_url('scripts2/tweaksettings?find=chkservd_plaintext_notify'),
        'tweaksettings_chkservd_recovery_notify_url'  => $self->assemble_whm_url('scripts2/tweaksettings?find=skip_chkservd_recovery_notify'),
        procdata                                      => scalar Cpanel::iContact::Utils::procdata_for_template_sorted_by_cpu( $self->_get_procdata_for_template() ),

        ( map { $_ => $self->{'_opts'}{$_} } $self->_OPTIONAL_TEMPLATE_ARGS_LIST() ),
    );
}

1;
