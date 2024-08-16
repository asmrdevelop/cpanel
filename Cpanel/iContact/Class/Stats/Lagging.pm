package Cpanel::iContact::Class::Stats::Lagging;

# cpanel - Cpanel/iContact/Class/Stats/Lagging.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::LoadCpConf ();
use Cpanel::iContact::Utils    ();

use parent qw(
  Cpanel::iContact::Class
);

my $ONE_HOUR = 60 * 60;

my @required_args = qw(
  origin
  user_lags
  cpanel_error_log_path
  cpanel_stats_log_path
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

    return (
        $self->SUPER::_template_args(),

        %{ $self->_get_system_info_template_vars() },

        procdata => scalar Cpanel::iContact::Utils::procdata_for_template_sorted_by_cpu( $self->_get_procdata_for_template() ),

        stats_cycle_length => $ONE_HOUR * Cpanel::Config::LoadCpConf::loadcpconf()->{'cycle_hours'},

        map { $_ => $self->{'_opts'}{$_} } (@required_args),
    );
}

1;
