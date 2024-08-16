package Cpanel::WebServer::Supported::apache::Handler::none;

# cpanel - Cpanel/WebServer/Supported/apache/Handler/none.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::WebServer::Supported::apache::Handler::none

=head1 DESCRIPTION

An Apache handler module which generates no configuration.  Turning
off global configurations is valid, though we recommend removing
unneeded language packages from the system instead.  The mime-type is
such that the contents of script files will be supplied, instead of
run via the appropriate interpreter.

A clearer documentation suite for the base class and an implemented
handler can be found in the I<SEE ALSO> section below.

=head1 TODO

Verify whether supplying the script contents is the desired behaviour.

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

sub new {
    my ( $class, %args ) = @_;
    my $self = bless( {}, $class );
    $self->init( \%args );
    return $self;
}

sub type {
    return 'none';
}

sub get_mime_type {
    my ($self) = @_;

    # This will most likely have the browser fetch the file contents,
    # which may not be what we want here.  Perhaps some mime handler
    # (or filter) which does nothing, to prevent script leakage?
    return 'text/plain';
}

sub get_config_string {
    my ($self) = @_;

    my $package = $self->get_package();
    return "# No configuration for $package\n";
}

1;
