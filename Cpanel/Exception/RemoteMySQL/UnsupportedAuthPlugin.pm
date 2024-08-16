package Cpanel::Exception::RemoteMySQL::UnsupportedAuthPlugin;

# cpanel - Cpanel/Exception/RemoteMySQL/UnsupportedAuthPlugin.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::RemoteMySQL::UnsupportedAuthPlugin

=head1 SYNOPSIS

    die Cpanel::Exception::create(
        'RemoteMySQL::UnsupportedAuthPlugin',
        'The [asis,MySQL] server uses the “[_1]” authentication plugin, which is not currently supported.',
        [ 'some_unsupported_plugin' ]
    );

=head1 DESCRIPTION

This exception class is for representing when an unsupported default authentication plugin
is used on a remote MySQL server.

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception );

1;
