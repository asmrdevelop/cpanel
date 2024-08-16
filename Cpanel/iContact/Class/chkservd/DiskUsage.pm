package Cpanel::iContact::Class::chkservd::DiskUsage;

# cpanel - Cpanel/iContact/Class/chkservd/DiskUsage.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::chkservd
);

my @optional_args = (

    # Bytes notification
    'used_bytes',
    'total_bytes',
    'available',

    # Inodes notification
    'used_inodes',
    'total_inodes',
    'available_inodes',
);

sub _TEMPLATE_ARGS_LIST {
    my ($self) = @_;

    return (
        $self->SUPER::_TEMPLATE_ARGS_LIST(),
        'mount',
        'notify_type',
        'filesystem',
        'usage_type',
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        'tweaksettings_system_diskusage_url'          => $self->assemble_whm_url('scripts2/tweaksettings?find=system_diskusage'),
        'tweaksettings_chkservd_plaintext_notify_url' => $self->assemble_whm_url('scripts2/tweaksettings?find=chkservd_plaintext_notify'),
        map { $_ => $self->{'_opts'}{$_} } (@optional_args),
    );
}

1;
