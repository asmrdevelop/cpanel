package Cpanel::WebServer::Supported::apache::Handler::fpm;

# cpanel - Cpanel/WebServer/Supported/apache/Handler/fpm.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::WebServer::Supported::apache::Handler::fpm

=head1 DESCRIPTION

An Apache handler module which supports the PHP-FPM FastCGI interface.
Most of the base functionality for this handler is unnecessary, so
most methods here do nothing.  The php-fpm webserver will implement
most of the necessary pool creation.

A clearer documentation suite for the base class and an implemented
handler can be found in the I<SEE ALSO> section below.

=head1 SEE ALSO

L<Cpanel::WebServer::Supported::apache::Handler::base>,
L<Cpanel::WebServer::Supported::apache::Handler::cgi>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

use parent 'Cpanel::WebServer::Supported::apache::Handler::base';

use strict;
use warnings;

use Cpanel::Imports;

sub new {
    my ( $class, %args ) = @_;

    my $self = bless( {}, $class );

    $self->init( \%args );
    $self->module_check_and( ['mod_proxy_fcgi'] );

    return $self;
}

sub type {
    return 'fpm';
}

1;
