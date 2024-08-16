package Cpanel::iContact::Class::dbindex::Warn;

# cpanel - Cpanel/iContact/Class/dbindex/Warn.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw(
  origin
  cache_file_path
);

my @template_args = (@required_args);

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
        'dbindex_path'         => '/usr/local/cpanel/bin/dbindex',
        'update_db_cache_path' => '/usr/local/cpanel/scripts/update_db_cache',
        map { $_ => $self->{'_opts'}{$_} } (@template_args)
    );
}

1;
