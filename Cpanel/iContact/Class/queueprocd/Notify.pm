package Cpanel::iContact::Class::queueprocd::Notify;

# cpanel - Cpanel/iContact/Class/queueprocd/Notify.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Services::Log ();
use Cpanel::ConfigFiles   ();

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw(
  origin
  cpanel_queueprocd_log_path
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
        map { $_ => $self->{'_opts'}{$_} } (@required_args)
    );
}

sub new {
    my ( $class, %args ) = @_;

    my $queueprocd_log_path = $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/queueprocd.log';

    my ( $cpanel_queueprocd_log_tail_status, $cpanel_queueprocd_log_tail_text ) = Cpanel::Services::Log::fetch_log_tail( $queueprocd_log_path, 300 );

    return $class->SUPER::new(
        %args,
        cpanel_queueprocd_log_path => $queueprocd_log_path,
        attach_files               => [
            { name => 'cpanel_queueprocd_log_tail.txt', content => \$cpanel_queueprocd_log_tail_text },
        ]
    );
}

1;
