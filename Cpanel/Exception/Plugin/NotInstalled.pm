package Cpanel::Exception::Plugin::NotInstalled;

# cpanel - Cpanel/Exception/Plugin/NotInstalled.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(  Cpanel::Exception );

use Cpanel::LocaleString ();

=encoding utf-8

=head1 NAME

Cpanel::Exception::Plugin::NotInstalled

=head1 SYNOPSIS

die Cpanel::Exception::create( 'Plugin::NotInstalled', [ plugin => 'plugin name' ] );

=head1 DESCRIPTION

This exception is for indicating that a specific plugin/rpm is not installed.

=cut

#metadata parameters:
#   plugin
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The “[_1]” plugin is not installed.',
        $self->get('plugin')
    );
}

1;
