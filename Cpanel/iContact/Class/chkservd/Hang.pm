package Cpanel::iContact::Class::chkservd::Hang;

# cpanel - Cpanel/iContact/Class/chkservd/Hang.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::chkservd
);

use Cpanel::iContact::Utils ();
use Cpanel::Services::Log   ();

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        'chkservd_tweaksetting_url'                   => $self->assemble_whm_url('scripts2/tweaksettings?find=chkservd'),
        'chkservd_plaintext_notify_tweaksettings_url' => $self->assemble_whm_url('scripts2/tweaksettings?find=chkservd_plaintext_notify'),
        procdata                                      => scalar Cpanel::iContact::Utils::procdata_for_template_sorted_by_cpu( $self->_get_procdata_for_template() ),
    );
}

sub _TEMPLATE_ARGS_LIST {
    my ($self) = @_;

    return (
        $self->SUPER::_TEMPLATE_ARGS_LIST(),
        'check_interval',
        'child_pid',
        'child_run_time',
        'cpanel_chkservd_log_path',
        'cpanel_tailwatchd_log_path',
    );
}

sub new {
    my ( $class, %args ) = @_;

    my $tailwatchd_log_path = $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/tailwatchd_log';
    my $chkservd_log_path   = '/var/log/chkservd.log';

    my ( $cpanel_chkservd_log_tail_status,   $cpanel_chkservd_log_tail_text )   = Cpanel::Services::Log::fetch_log_tail( $chkservd_log_path,   300 );
    my ( $cpanel_tailwatchd_log_tail_status, $cpanel_tailwatchd_log_tail_text ) = Cpanel::Services::Log::fetch_log_tail( $tailwatchd_log_path, 300 );

    return $class->SUPER::new(
        %args,
        cpanel_chkservd_log_path   => $chkservd_log_path,
        cpanel_tailwatchd_log_path => $tailwatchd_log_path,
        attach_files               => [
            { name => 'cpanel_chkservd_log_tail.txt',   content => \$cpanel_chkservd_log_tail_text },
            { name => 'cpanel_tailwatchd_log_tail.txt', content => \$cpanel_tailwatchd_log_tail_text },
        ]
    );
}

1;
