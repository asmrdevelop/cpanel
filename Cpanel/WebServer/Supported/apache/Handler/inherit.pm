package Cpanel::WebServer::Supported::apache::Handler::inherit;

# cpanel - Cpanel/WebServer/Supported/apache/Handler/inherit.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::WebServer::Supported::apache::Handler::inherit

=head1 DESCRIPTION

The 'inherit' handler is a concept that cPanel created to represent
how Apache processes .htaccess files during a request.  Let's use the
following as an example:

    /home/user/public_html/.htaccess
    /home/user/public_html/subdir/.htaccess
    /home/user/public_html/subdir/application.cgi

The above shows 2 .htaccess files.  One file is directly within the
document root of the user's virtual host.  The other is within a
subdirectory of that same document root.

When a request comes in for application.cgi, Apache will first pick
up the settings within /home/user/public_html/.htaccess.  After,
it will then pick up any additional settings within
/home/user/public_html/subdir/.htaccess, and potentially override
previously defined values.  Thus, the contents of /subdir/ "inherit"
the settings above it.

The result is that 'inheriting' an Apache handler, is nothing more
than removing .htaccess entries that would tell Apache to use a
different handler.

For more information on handler implementation, please refer to the
I<SEE ALSO> section below.

=head1 SEE ALSO

L<Cpanel::WebServer::Supported::apache::Handler::base>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

use parent 'Cpanel::WebServer::Supported::apache::Handler::base';
use strict;
use warnings;
use Cpanel::Imports;
use Cpanel::Exception ();

sub new {
    my ( $class, %args ) = @_;
    my $self = bless( {}, $class );
    $self->init( \%args );
    return $self;
}

sub type {
    return 'inherit';
}

sub get_mime_type {
    my ($self) = @_;
    die Cpanel::Exception::create( 'AttributeNotSet', q{You can not set a package to the “[_1]” [asis,Apache] handler.}, [ $self->type() ] );
}

sub get_config_string {
    my ($self) = @_;
    die Cpanel::Exception::create( 'AttributeNotSet', q{You can not set a package to the “[_1]” [asis,Apache] handler.}, [ $self->type() ] );
}

sub get_default_string {
    my ($self) = @_;
    die Cpanel::Exception::create( 'AttributeNotSet', q{You can not set a package to the “[_1]” [asis,Apache] handler.}, [ $self->type() ] );
}

sub get_htaccess_string {
    my ($self) = @_;
    return '# ' . locale->maketext( q{This domain inherits the “[_1]” package.}, uc $self->get_lang()->type() );
}

1;
