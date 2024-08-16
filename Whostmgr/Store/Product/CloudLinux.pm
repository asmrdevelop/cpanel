
# cpanel - Whostmgr/Store/Product/CloudLinux.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Store::Product::CloudLinux;

use strict;
use warnings;
use Cpanel::CloudLinux ();
use Cpanel::OS         ();

use Cpanel::Locale 'lh';

use base 'Whostmgr::Store';

=head1 NAME

Whostmgr::Store::Product::CloudLinux - Purchase and install implementation
subclass for CloudLinux

=cut

###########################################################
# Constants
###########################################################

use constant HUMAN_PRODUCT_NAME => 'CloudLinux';

# License system
use constant PRODUCT_ID    => 'CloudLinux';
use constant PACKAGE_ID_RE => qr/-CLOUDLINUX-/;    # e.g., PARTNERNAME-CLOUDLINUX-UNLIMITED or ANOTHERNAME-CLOUDLINUX-SOLO
use constant CPLISC_ID     => 'cloudlinux';

# Store
use constant STORE_ID_UNLIMITED => 113;            # monthly
use constant STORE_ID_SOLO      => 113;            # monthly

# Manage2
use constant MANAGE2_PRODUCT_NAME => 'cloudlinux';

# Everything else ...
use constant RPM_NAME           => 'cloudlinux-release';                                            # RPM Name
use constant INSTALL_GET_URL    => 'https://repo.cloudlinux.com/cloudlinux/sources/cln/cldeploy';
use constant PID_FILE           => '/var/run/store-cloudlinux-install-running';
use constant LOG_PATH           => '/var/cpanel/logs/cloudlinux-install.log';
use constant PURCHASE_START_URL => 'scripts13/purchase_cloudlinux_init';

sub IS_AVAILABLE_ON_THIS_OS {
    return Cpanel::OS::can_become_cloudlinux();
}

use constant SERVER_TYPE_AVAILABILITY => {
    standard  => 1,
    vm        => 1,
    container => 0,
};

use constant HOST_LICENSE_TYPE_AVAILABILITY => {
    unlimited => 1,
    solo      => 1,
};

###########################################################
# Implementation of core functionality
###########################################################

=head1 OBJECT INTERFACE

The purchase and install interface of this class is the same one
offered by the parent class. See C<Whostmgr::Store> for documentation
on this.

=head1 IMPLEMENTATION METHODS (not meant to be called directly)

=head2 install_implementation()

The implementation of the installation. This is not meant to be called
directly, but rather as part of the install interface offered by the
parent class.

=cut

sub install_implementation {
    my ($self) = @_;

    Cpanel::CloudLinux::install_cloudlinux();

    return 1;
}

=head2 handle_error()

The error handling implementation. This is not meant to be called directly.

=cut

sub handle_error {
    my ( $self,  %args ) = @_;
    my ( $error, $_at )  = @args{qw(error _at)};
    $self->_print($error) if $error;    # seen in browser briefly until the refresh
    $self->logger->warn( sprintf( "%s%s%s", $error, ($_at) ? q{: } : q{}, ($_at) ? $_at : q{} ) );

    my $redirect_url = $self->build_redirect_url( $self->{redirect_path} );
    return $self->_refresh( $redirect_url, 5 );
}

1;
