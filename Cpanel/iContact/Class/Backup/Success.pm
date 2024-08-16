package Cpanel::iContact::Class::Backup::Success;

# cpanel - Cpanel/iContact/Class/Backup/Success.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Time::Split ();

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw(origin start_time end_time);
my @args          = qw(transport_started log_file_path);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args,
    );
}

sub _template_args {
    my ($self) = @_;

    my %template_args = (
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } ( @required_args, @args ),
    );

    $template_args{'run_time_localized'} = Cpanel::Time::Split::seconds_to_locale( $self->{'_opts'}{'end_time'} - $self->{'_opts'}{'start_time'} );

    return %template_args;
}

1;
