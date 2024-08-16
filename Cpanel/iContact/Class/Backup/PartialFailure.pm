package Cpanel::iContact::Class::Backup::PartialFailure;

# cpanel - Cpanel/iContact/Class/Backup/PartialFailure.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Time::Split ();

use parent qw(
  Cpanel::iContact::Class
);

sub new {
    my ( $class, %args ) = @_;

    return $class->SUPER::new(%args);
}

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        'origin',
        'start_time',
        'end_time',
    );
}

sub _template_args {
    my ($self) = @_;

    my %template_args = (
        $self->SUPER::_template_args(),

        map { $_ => $self->{'_opts'}{$_} } (
            qw(
              origin
              is_legacy
              major_error
              important_errors
              local_copy_errors
              transport_errors
              account_errors
              transport_started
              log_file_path
            ), $self->_required_args()
        )
    );

    $template_args{'run_time_localized'} = Cpanel::Time::Split::seconds_to_locale( $self->{'_opts'}{'end_time'} - $self->{'_opts'}{'start_time'} );
    return %template_args;
}

1;
