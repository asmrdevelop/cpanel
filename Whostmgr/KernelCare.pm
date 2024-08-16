package Whostmgr::KernelCare;

# cpanel - Whostmgr/KernelCare.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::NAT         ();
use JSON::XS            ();
use Cpanel::DIp::MainIP ();
use Cpanel::cPStore     ();

our $REFRESH_DELAY = 5;                                                                     # seconds
use constant KERNELCARE_PACKAGE_NAME => q{kernelcare};
our $KERNELCARE_INSTALL_URL     = q{https://repo.cloudlinux.com/kernelcare};
our $KERNELCARE_INSTALL_SCRIPT  = q{kernelcare_install.sh};
our $KERNELCARE_INSTALL_GET_URL = qq{$KERNELCARE_INSTALL_URL/$KERNELCARE_INSTALL_SCRIPT};
our $KERNELCARE_INSTALL_TIMEOUT = 180;                                                      # seconds

sub new {
    my $pkg  = shift;
    my $self = {
        'access_token' => undef,
        'mainserverip' => undef,
    };
    bless $self, $pkg;
    return $self;
}

sub get_login_url {
    my ( $self, $host, $port, $security_token, $path ) = @_;

    # create refresh url to handle OAuth2 login callback (on authentication)
    my $refresh_url = sprintf( "https://%s:%s%s/%s", $host, $port, $security_token, $path );

    # return url to user uses to authenticate OAuth2 token
    my $login_url = Cpanel::cPStore::LOGIN_URI($refresh_url);
    return $login_url;
}

sub validate_login_token {
    my ( $self, $host, $port, $security_token, $path, $code ) = @_;

    # create refresh url to handle OAuth2 login callback (on authentication)
    my $refresh_url = sprintf( "https://%s:%s%s/%s", $host, $port, $security_token, $path );
    local $@;
    my $response = eval { Cpanel::cPStore::validate_login_token( $code, $refresh_url ) };
    die $@ if $@;    # throw error to caller

    if ( $response->{'token'} ) {
        $self->access_token( $response->{'token'} );
    }
    return $self->access_token();
}

sub create_shopping_cart {
    my ( $self, $host, $port, $security_token, $path ) = @_;
    my $refresh_url = sprintf( "https://%s:%s%s/%s", $host, $port, $security_token, $path );
    local $@;
    require Cpanel::Market::Provider::cPStore;
    my ( $order_id, $order_items_ref ) = eval {
        Cpanel::Market::Provider::cPStore::create_shopping_cart(
            access_token       => $self->access_token(),
            url_after_checkout => $refresh_url,
            items              => [
                {
                    'product_id' => $self->get_kernelcare_product_id(),
                    'ips'        => [ $self->mainserverip() ],
                }
            ],
        );
    };
    die $@ if $@;    # throw error to caller

    my $checkout_url = Cpanel::cPStore::CHECKOUT_URI_WHM($order_id);
    return $order_id, $order_items_ref, $checkout_url;
}

sub access_token {
    my $self = shift;
    if ( my $token = shift ) {
        $self->{'access_token'} = $token;
    }
    return $self->{'access_token'};
}

sub mainserverip {
    my $self = shift;
    if ( not $self->{'mainserverip'} ) {
        $self->{'mainserverip'} = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );
    }
    return $self->{'mainserverip'};
}

sub get_kernelcare_product {
    my $self         = shift;
    my $store        = Cpanel::cPStore->new();
    my $product_list = $store->get('products/cpstore');
    foreach my $product (@$product_list) {
        return $product if $product->{'short_name'} eq q{Monthly KernelCare};
    }
    return;
}

sub get_kernelcare_product_id {
    my $self    = shift;
    my $product = $self->get_kernelcare_product();
    return $product->{'item_id'};
}

sub get_kernelcare_product_price {
    my $self    = shift;
    my $product = $self->get_kernelcare_product();
    return $product->{'price'};
}

sub _find_bash_bin {
    for my $path (qw ( /bin/bash )) {
        if ( -x $path ) {
            return $path;
        }
    }
    return undef;
}

sub _install_kernelcare {

    require Cpanel::HTTP::Client;
    require Cpanel::TempFile;
    require Cpanel::SafeRun::Object;

    # get script from $KERNELCARE_INSTALL_GET_URL
    local $@;
    my $response = eval {
        my $http = Cpanel::HTTP::Client->new( verify_SSL => 1 )->die_on_http_error();
        $http->get($KERNELCARE_INSTALL_GET_URL);
    };
    die $@ if $@;

    # Dump script (response content) to a file to run
    my $tmp      = Cpanel::TempFile->new;
    my $filename = $tmp->file();

    # write script (via response contents) to temp $filename
    open my $fh, q{>}, $filename or die qq{Can't open $filename: $!};
    print $fh $response->{'content'};
    close $fh;

    # get safe bash path
    my $bash_bin = _find_bash_bin();

    # execute $filename to install
    my $run = Cpanel::SafeRun::Object->new(
        program => $bash_bin,
        args    => [$filename],
        timeout => $KERNELCARE_INSTALL_TIMEOUT,
    );
    return $run;
}

sub is_installed {
    require Cpanel::Pkgr;
    return Cpanel::Pkgr::is_installed(KERNELCARE_PACKAGE_NAME);
}

sub ensure_kernelcare_installed {
    my $self = shift;

    # install
    if ( !is_installed ) {
        _install_kernelcare();
    }

    return is_installed();
}

sub return_to_security_advisor {
    my ( $self, $host, $port, $security_token, $delay ) = @_;
    my $path                 = q{cgi/securityadvisor/index.cgi};
    my $security_advisor_url = sprintf( "https://%s:%s%s/%s", $host, $port, $security_token, $path );
    return $self->_refresh( $security_advisor_url, $delay );
}

sub _refresh {
    my ( $self, $url, $delay ) = @_;
    require Cpanel::Encoder::Tiny;
    $url   = Cpanel::Encoder::Tiny::safe_html_encode_str($url);
    $delay = ( defined $delay ) ? int $delay : $REFRESH_DELAY;
    return print qq{<meta http-equiv="refresh" content="$delay; url=$url" />};
}

sub _print {
    my $self     = shift;
    my $to_print = shift;
    return print $to_print;
}

# error handler implemented for use with KernelCare integration
sub _handle_kc_error {
    my ( $self, $logger, $error, $_at, $host, $port, $security_token ) = @_;
    $self->_print($error) if $error;    # seen in browser briefly until the refresh
    $logger->warn( sprintf( "%s%s%s", $error, ($_at) ? q{: } : q{}, ($_at) ? $_at : q{} ) );
    return $self->return_to_security_advisor( $host, $port, $security_token );
}

1;

__END__

=head1 NAME

Whostmgr::KernelCare - encapsulates much of the behavior related to the purchase and installion of KernelCare through WHM

=head1 SYNOPSIS

  my $handler = Whostmgr::KernelCare->new();

  #... see whostmgr/bin/whostmgr12.pl for main use of this module

=head1 DESCRIPTION

This module was created to manage the implementation of the KernelCare purchase and installation
workflow via WHM. It's really not meant to be used outside of that flow, but there might be some
useful methods here.

=head1 METHODS

=over 4

=item new

Constructor method used normally, takes no arguments

=item get_login_url

Generates the login URL needed for refreshing user to enter in their OAuth2 credentials

=item validate_login_token

Upon successful authentication, contacts the auth server to verify the authentication and gets that actual OAuth2 token

=item create_shopping_cart

Uses an authenticated OAuth2 token to create a valid shopping cart session in the cPanel Store

=item access_token

Setter/getter for the API token; it's on of two actual fields in this class

=item mainserverip

Determines public facing IP address and stores it as a class field if not already set; return main server ip address.

=item get_kernelcare_product

Makes a call to the cPanel Store returning the monthly KernelCare package

=item get_kernelcare_product_id

Makes a call to the cPanel Store to determine the actual item_id used by the monthly KernelCare package

=item get_kernelcare_product_price

Makes a call to the cPanel Store to determine the actual price used by the monthly KernelCare package

=item ensure_kernelcare_installed

Manages checking for and installing the KernelCare RPM upon successful purchase; the actual installation procedure
is encapsulated in the internal method, C<_install_kernelcare> (see below in L<INTERNAL METHODS>).

=item return_to_security_advisor

Redirects back to WHM with SecurityAdvisor loaded as the main frame target

=back

=head2 INTERNAL METHODS

=over 4

=item _verify_kernelcare_license

REMOVED -- Use Cpanel::KernelCare::Availability::system_license_from_cpanel()

=item _install_kernelcare

Implements the installation process for KernelCare. It is bound to change over time, this is here it happens.

=item _print

Wrapper around Perl's print so that it can be silenced during test.

=item _refresh

Requires 1 parameter (refresh URL). Accepts a second optional parameter to set the refresh delay. Default is the value of the package variable C<$Whostmgr::KernelCare::REFRESH_DELAY>.

Delayed refresh via meta refresh tag, separated out for testing purposes.

=item _handle_kc_error

General error handler, used when $@ is detected or some other error needs to halt the KernelCare purchase process. Logs all errors.

=back

=head1 LICENSE AND COPYRIGHT

Copyright 2022, cPanel, Inc. All rights reserved.
