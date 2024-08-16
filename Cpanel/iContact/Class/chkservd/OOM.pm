package Cpanel::iContact::Class::chkservd::OOM;

# cpanel - Cpanel/iContact/Class/chkservd/OOM.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::chkservd
);

use Cpanel::iContact::Utils ();

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        'service_manager_url'                         => $self->assemble_whm_url('scripts/srvmng#service-chkservd'),
        'tweaksettings_chkservd_url'                  => $self->assemble_whm_url('scripts2/tweaksettings?find=chkservd'),
        'tweaksettings_chkservd_plaintext_notify_url' => $self->assemble_whm_url('scripts2/tweaksettings?find=chkservd_plaintext_notify'),
        procdata                                      => scalar Cpanel::iContact::Utils::procdata_for_template_sorted_by_mem( $self->_get_procdata_for_template() ),
        ( map { $_ => $self->{'_opts'}{$_} } $self->_OPTIONAL_TEMPLATE_ARGS_LIST() ),
    );
}

sub _OPTIONAL_TEMPLATE_ARGS_LIST {
    my ($self) = @_;

    return (
        'data',
        'uid',
        'user',
        'pid',
        'proc_name',
        'time',
        'score',
        'total_vm',
        'anon_rss',
        'file_rss',
        'process_killed',
    );
}

1;
