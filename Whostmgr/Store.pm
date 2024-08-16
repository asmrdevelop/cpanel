
# cpanel - Whostmgr/Store.pm                       Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Whostmgr::Store;

use strict;
use warnings;
use Carp ();

use Cpanel::Autowarn                         ();
use Cpanel::Config::Sources                  ();
use Cpanel::cPStore                          ();
use Cpanel::Daemonizer::Tiny                 ();
use Cpanel::DIp::MainIP                      ();
use Cpanel::Encoder::Tiny                    ();
use Cpanel::Encoder::URI                     ();
use Cpanel::Exception                        ();
use Cpanel::FileUtils::Write                 ();
use Cpanel::HTTP::Client                     ();
use Cpanel::JSON                             ();
use Cpanel::Logger                           ();
use Cpanel::Market::Provider::cPStore        ();
use Cpanel::Market::Provider::cPStore::Utils ();
use Cpanel::NAT                              ();
use Cpanel::PIDFile                          ();
use Cpanel::Pkgr                             ();
use Cpanel::SafeRun::Object                  ();
use Cpanel::Server::Type                     ();
use Cpanel::Services::Ports                  ();
use File::Temp                               ();
use Cpanel::HTTP::QueryString                ();
use Whostmgr::API::1::Utils::Execute         ();

use Cpanel::Locale 'lh';

=encoding utf-8

=head1 NAME

Whostmgr::Store - Common module for cPanel Store purchase & install process
within WHM

=head1 DESCRIPTION

This module is intended to be used as a parent class for your purchase/install
module implementation.

=head1 SUBCLASS MUST IMPLEMENT THESE ATTRIBUTE METHODS

You must implement the following attribute methods which are effectively
constants for your implementation.  It is recommended that you implement
these via C<use constant ...>.

=over

=item * HUMAN_PRODUCT_NAME
The human-friendly product name for the purpose of embedding in status
messages that get sent to the browser.

=item * PRODUCT_ID
The product id used in the cPanel license system. There should be a single
id per product.

=item * PACKAGE_ID_RE
A regular expression (qr//) to match the package id in the cPanel license
system. There may be multiple package ids per product.

=item * CPLISC_ID
The product as used in the products field of the cpanel.lisc file.

=item * STORE_ID_UNLIMITED
The short product name used in the cPanel store when the product is being
purchased on a standard (not Solo) cPanel server.

=item * STORE_ID_SOLO
The short product name used in the cPanel store when the product is being
purchased on a cPanel Solo server.

=item * RPM_NAME
The RPM package name for the product when it is installed. If the product
is not RPM-managed, provide some dummy data here and then override the
is_product_installed method instead.

=item * INSTALL_GET_URL
The URL from which to download the latest installer for the product. If
your implementation does not download the installer, provide some dummy
data here and then override the get_installer method.

=item * PID_FILE
The PID file to use for the install process. This should be
something unique to whichever product is being installed. Suggestion:
/var/run/[productname]_install.pid

=item * LOG_PATH
The path to the installation log. This is used for two purposes:

=item * PURCHASE_START_URL

A whostmgrX route which begins the purchase workflow for the product.

=over

=item * In your own implementation, you should use this attribute to
determine where the installation log is written.

=item * In the templates used by Whostmgr::Store::Template, this path is
used for generating a message informing the user of where to find the
installation log.

=back

=item * is_available_on_this_os

Determines if this feature should be advertised based on the installed distro.

=item * SERVER_TYPE_AVAILABILITY
A hash ref with keys standard,vm,container, each of which is a boolean
indicating whether the product is available in that type of server
environment.

=item * HOST_LICENSE_TYPE_AVAILABILITY
A hash ref with keys unlimited,solo, each of which is a boolean indicating
whether the product is available on that cPanel & WHM license type.

=back

=head1 SUBCLASS MUST IMPLEMENT THESE INSTANCE METHODS

=head2 install_implementation()

The actual installation method. This method may call get_installer() if
applicable or it may set the installer up in its own way.

=head3 Arguments

none

=head3 Returns

nothing

=head3 Throws

The implementor may optionally throw the following exception, which will
influence the outcome of the install operation:

=over

=item * Cpanel::Exception::Store::PartialSuccess - Provide the "detail"
field for the exception. This will be converted into an overall "success"
outcome, but the additional detail about what failed will be made available
in the additional detail field returned by C<ensure_installed()>. The caller
may then (optionally) present this information to the user as part of the
success message.

=back

=head2 handle_error( error => ..., _at => ... )

A method that decides what to do when an error occurs. The simplest
implementation of this would be printing a message to stdout so that it
gets displayed in the browser.

=head3 ARGUMENTS

Key/value pairs:

=over

=item * error - String - The error message, if any

=item * _at - String - The contents of $@, if any

=back

=head1 OPTIONAL CONSTANTS

=over

=item * INSTALL_DURATION_WARNING
An int to display the estimated amount of time, in minutes, for an install to take in the template

=item * BACKGROUND_INSTALL
A flag to inform the user if an install will take place in the background
and a page can be navigated away from.

=back

=cut

my %required_attributes = (
    HUMAN_PRODUCT_NAME             => 'The human-friendly product name for the purpose of embedding in status messages that get sent to the browser.',
    PRODUCT_ID                     => 'The product id used in the cPanel license system. There should be a single id per product.',
    PACKAGE_ID_RE                  => 'A regular expression (qr//) to match the package id in the cPanel license system. There may be multiple package ids per product.',
    CPLISC_ID                      => 'The product as used in the products field of the cpanel.lisc file.',
    STORE_ID_UNLIMITED             => 'The short product name used in the cPanel store when the product is being purchased on a standard (not Solo) cPanel server.',
    STORE_ID_SOLO                  => 'The short product name used in the cPanel store when the product is being purchased on a cPanel Solo server.',
    RPM_NAME                       => 'The RPM package name for the product when it is installed. If the product is not RPM-managed, provide some dummy data here and then override the is_product_installed method instead.',
    INSTALL_GET_URL                => 'The URL from which to download the latest installer for the product. If your implementation does not download the installer, provide some dummy data here and then override the get_installer method.',
    PID_FILE                       => 'The PID file to use for the install process. This should be something unique to whichever product is being installed. Suggestion: /var/run/[productname]_install.pid',
    LOG_PATH                       => 'The path to the installation log. This is used for two purposes: (1) In your own implementation, you should use this attribute to determine where the installation log is written. (2) In the templates used by Whostmgr::Store::Template, this path is used for generating a message informing the user of where to find the installation log.',
    SERVER_TYPE_AVAILABILITY       => 'A hash ref with keys standard,vm,container, each of which is a boolean indicating whether the product is available in that type of server environment.',
    HOST_LICENSE_TYPE_AVAILABILITY => 'A hash ref with keys unlimited,solo, each of which is a boolean indicating whether the product is available on that cPanel & WHM license type.',
    MANAGE2_PRODUCT_NAME           => 'The name of the product in Manage2, for the purpose of locating the <product>.cgi script to check disabled state.',
    PURCHASE_START_URL             => 'The WhostmgrX route which begins the purchase workflow when partners do not override this with their own url.',
);

my %required_methods = (
    install_implementation => 'The actual installation method. This method may call get_installer() if applicable or it may set the installer up in its own way.',
    handle_error           => 'A method that decides what to do when an error occurs. The simplest implementation of this would be printing a message to stdout so that it gets displayed in the browser.',
);

use constant {
    INSTALL_DURATION_WARNING => undef,
    BACKGROUND_INSTALL       => 0
};

sub validate_implementation {
    my ($package_or_self) = @_;

    for my $attr ( sort keys %required_attributes ) {
        my $value = $package_or_self->can($attr) && $package_or_self->$attr;
        if ( !$value ) {
            Carp::confess("You must implement the ‘$attr’ attribute method: $required_attributes{$attr}");
        }
    }

    for my $attr ( sort keys %required_methods ) {
        if ( !$package_or_self->can($attr) ) {
            Carp::confess("You must implement the ‘$attr’ method: $required_methods{$attr}");
        }
    }

    $package_or_self->can('IS_AVAILABLE_ON_THIS_OS') or Carp::confess("You have not implemented IS_AVAILABLE_ON_THIS_OS in your Class");

    my $server_type_availability = $package_or_self->SERVER_TYPE_AVAILABILITY;
    for my $server_type (qw(standard vm container)) {
        my $value = $server_type_availability->{$server_type} // '';
        if ( $value ne '0' && $value ne '1' ) {
            Carp::confess("You must include a true/false value represented as 1 or 0 for ‘$server_type’ in the SERVER_TYPE_AVAILABILITY information.");
        }
    }

    my $host_license_type_availability = $package_or_self->HOST_LICENSE_TYPE_AVAILABILITY;
    for my $license_type (qw(unlimited solo)) {
        my $value = $host_license_type_availability->{$license_type} // '';
        if ( $value ne '0' && $value ne '1' ) {
            Carp::confess("You must include a true/false value represented as 1 or 0 for ‘$license_type’ in the HOST_LICENSE_TYPE_AVAILABILITY information.");
        }
    }

    return;
}

=head1 MAIN OBJECT INTERFACE PROVIDED BY COMMON CLASS

=head2 new()

Constructor method.

Arguments (key/value pairs):

=over

=item * redirect_path - String - (Required) The relative path in WHM (without security token) to redirect to
after a success or failure.

=item * logger - Cpanel::Logger object - (Optional) If provided, the internal error-handling of Whostmgr::Store
will use this logger instance instead of creating one.

=item * app - WHM App this code may be loaded from.  Used for UTM tags in redirect urls.

=item * source - Component from which this is coming from.  Used for UTM tags in redirect urls.  Default is cpanel_store.

=back

=cut

sub new {
    my ( $pkg, %args ) = @_;

    $pkg->validate_implementation;

    my $self = {
        'access_token'   => undef,
        'mainserverip'   => undef,
        'port'           => $ENV{'SERVER_PORT'},
        'host'           => $ENV{'HTTP_HOST'},
        'security_token' => $ENV{'cp_security_token'},
        '_whm_app'       => $args{app}    || '',
        '_source'        => $args{source} || 'cpanel_store',
    };

    $self->{redirect_path} = $args{redirect_path} || Carp::croak('You must provide the redirect_path parameter');

    $self->{logger} = $args{logger} || Cpanel::Logger->new();

    bless $self, $pkg;
    return $self;
}

=head2 STEP 1: should_offer()

Returns a boolean indicating whether the product should be offered for
purchase/install.

This is determined by a combination of checks:

=over

=item * Is the product supported on this distro and OS version?

=item * Is the server type (dedicated, VM, container) supported?

=item * Has a partner disabled the product via Manage2 for this IP?

=back

=cut

sub should_offer {
    my ($self) = @_;

    return
         $self->os_supported()
      && $self->server_type_supported()
      && $self->host_license_type_supported()
      && !$self->get_manage2_data( $self->MANAGE2_PRODUCT_NAME )->{'disabled'} ? 1 : 0;
}

=head2 STEP 2: get_login_url(PATH)

Generates the login URL needed to log in to the cPanel store. The PATH
argument that is passed in is used for building the "refresh URL", which
is the URL in WHM that you are sent back to after the authentication step.

=head3 ARGUMENTS

=over

=item PATH - String - The WHM path to redirect to after the authentication step (with or without leading slash)

=back

=head3 RETURNS

The login URL that includes the redirect URL back into WHM

=cut

sub get_login_url {
    my ( $self, $path ) = @_;

    # create refresh url to handle OAuth2 login callback (on authentication)
    my $refresh_url = $self->build_redirect_url($path);

    # return url to user uses to authenticate OAuth2 token
    my $login_url = Cpanel::cPStore::LOGIN_URI($refresh_url);
    return $login_url;
}

=head2 STEP 3: validate_token_and_create_shopping_cart( code, checkout_path, completion_path )

Validates the login token you received in the previous step and then sets
up the Store shopping cart with the product you wish to purchase.

If anything during this process fails, the error handler supplied by the
implementor in C<handle_error()> will be used, and an empty list will
be returned.

If you need to customize your error handling, it is recommended that you
provide your own C<handle_error()> method in your implementation module
rather than attempting to directly catch and handle the exceptions thrown
by individual steps of this process.

=head3 ARGUMENTS

=over

=item code - String - The login token

=item checkout_path - String - The URL for the checkout stage

=item completion_path - String - The WHM path to redirect to after checkout (with or
without leading slash)

=back

=head3 RETURNS

A list with:

=over

=item - Number - The order id

=item - Array ref - The order items

=item - String - The checkout URL for the order that was created

=back

=cut

sub validate_token_and_create_shopping_cart {
    my ( $self, $code, $checkout_path, $completion_path ) = @_;

    eval { $self->validate_login_token( $checkout_path, $code ); };
    if ( my $exception = $@ ) {
        $self->handle_error(
            error => q{The system failed to validate the login token.},
            _at   => $exception,
        );
        return;
    }

    my ( $order_id, $order_items_ref, $checkout_url ) = eval { $self->create_shopping_cart($completion_path); };
    if ( my $exception = $@ ) {
        $self->handle_error(
            error => q{The system failed to create the shopping cart.},
            _at   => $exception,
        );
        return;
    }

    return ( $order_id, $order_items_ref, $checkout_url );
}

=head2 STEP 4: check_order_status_and_license_status(FORMREF)

Check that 1) the Store reported the order as a success and 2) the product
in question now shows up as licensed. In the case of failure, this function
produces an error response visible to the user.

=head3 ARGUMENTS

Key/value pairs:

=over

=item * success - Boolean - This value passed in by the caller indicates
whether the purchase operation succeeded or not. This should be determined
based on the response from the Store.

=back

=head3 RETURNS

Boolean indicating success or failure

=cut

sub check_order_status_and_license_status {
    my ( $self, %args ) = @_;

    my $license_verified;
    if ( $args{success} ) {
        _sleep(10);    # License refreshes need to wait a few minutes, so let's give a chance for the license system to catch up before our one and only pre-install verification.
        local $@;
        my $license_verified = eval { $self->is_product_licensed( cache => 0 ); };
        if ( my $exception = $@ ) {
            $self->handle_error(
                error => q{Attempt to verify license failed.},
                _at   => $exception,
            );
            return 0;
        }
        if ( !$license_verified ) {
            my $msg = q{The product license does not appear to be active yet.};
            $self->handle_error(
                error => $msg,
                _at   => undef,
            );
            return 1;    # proceed anyway under the assumption that
        }
    }
    else {
        my $msg = q{Successful order not detected.};
        $self->handle_error(
            error => $msg,
            _at   => undef,
        );
        return 0;
    }

    return 1;
}

=head2 STEP 5: ensure_installed()

Checks whether the product is already installed, and if not, installs it.

Returns a list with:

=over

=item * Boolean - Whether the product is actually installed

=item * String - Any additional detail (may not be present)

=back

=cut

sub ensure_installed {
    my ($self) = @_;

    # If the install is still running, proceed down to $self->install below to reattach and monitor it
    my $install_pid     = eval { Cpanel::PIDFile->get_pid( $self->PID_FILE ) };
    my $install_running = $install_pid && kill( 0, $install_pid );

    if ( !$install_running && ( my $is_installed = $self->is_product_installed() ) ) {
        return $is_installed;
    }

    my ( $install_ok, $install_detail ) = $self->install();

    # return with final result of is_product_installed check
    my $installed = $self->is_product_installed();
    if ( $install_ok && $installed ) {
        return ( 1, $install_detail );
    }
    elsif ($install_ok) {
        return ( 0, sprintf( 'Installation of %s finished, but the software could not be detected on the system.', $self->HUMAN_PRODUCT_NAME ) );
    }
    else {
        return ( 0, $install_detail );
    }

}

=head1 ADDITIONAL METHODS THAT MAY BE NEEDED AS PART OF YOUR IMPLEMENTATION

=head2 validate_login_token(path, code)

Upon successful authentication, contacts the auth server to verify the
authentication and gets that actual OAuth2 token.  The path argument passed
in is for building the redirect URL back into WHM after the token check.

=head3 ARGUMENTS

=over

=item PATH - String - The WHM path to redirect to after the token check
(with or without leading slash)

=item CODE - String - The login token

=back

=head3 RETURNS

String - The OAuth access token

=cut

sub validate_login_token {
    my ( $self, $path, $code ) = @_;

    if ( !$code ) {
        return $self->handle_error(
            error => q{Missing required parameter.},
            _at   => undef,
        );
    }

    # create refresh url to handle OAuth2 login callback (on authentication)
    my $refresh_url = $self->build_redirect_url($path);

    # Strip the GET parameters if any for login token
    ($refresh_url) = split( /\?/, $refresh_url );

    my $response = Cpanel::cPStore::validate_login_token( $code, $refresh_url );

    if ( $response->{'token'} ) {
        $self->access_token( $response->{'token'} );
    }
    return $self->access_token();
}

=head2 create_shopping_cart(PATH)

Uses an authenticated OAuth2 token to create a valid shopping cart session in the cPanel Store.

=head3 ARGUMENTS

=over

=item PATH - String - The WHM path to redirect to after checkout (with or
without leading slash)

=back

=head3 RETURNS

A list with:

=over

=item - Number - The order id

=item - Array ref - The order items

=item - String - The checkout URL for the order that was created

=back

=cut

sub create_shopping_cart {
    my ( $self, $path ) = @_;
    my $refresh_url = $self->build_redirect_url($path);
    my ( $order_id, $order_items_ref ) = Cpanel::Market::Provider::cPStore::create_shopping_cart(
        access_token       => $self->access_token(),
        url_after_checkout => $refresh_url,
        items              => [
            {
                'product_id' => scalar $self->get_product_id(),
                'ips'        => [ $self->mainserverip() ],
            }
        ],
    );

    my $checkout_url = Cpanel::cPStore::CHECKOUT_URI_WHM($order_id);
    return ( $order_id, $order_items_ref, $checkout_url );
}

=head2 get_installer()

In the default implementation, this fetches the installer from an HTTP
server based on the value of the INSTALL_GET_URL attribute method. You
should use the get_installer() method in your install_implementation()
method. If this approach to retrieving the installer is not applicable, feel
free to override the get_installer() method in your implementation. However,
do remember to keep the same return type with the temp object so as not to
break the interface.

=head3 RETURNS

A list with:

- Temp object: This instance must be retained until you are ready for the
installer file to be deleted.

- Temp filename of installer.

=cut

sub get_installer {
    my ($self) = @_;

    my $response = eval {
        my $http = Cpanel::HTTP::Client->new()->die_on_http_error();
        $http->get( $self->INSTALL_GET_URL );
    };
    if ( my $exception = $@ ) {
        die lh()->maketext( 'The system could not fetch the installation script: [_1]', $exception );
    }

    my ( $temp, $temp_filename ) = _installer_tempfile();

    Cpanel::FileUtils::Write::overwrite( $temp_filename, $response->{'content'} );

    return ( $temp, $temp_filename );
}

=head2 mainserverip()

Determines public facing IP address and stores it as a class field if not
already set; return main server IP address (String).

=cut

sub mainserverip {
    my $self = shift;
    if ( not $self->{'mainserverip'} ) {
        $self->{'mainserverip'} = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );
    }
    return $self->{'mainserverip'};
}

=head2 access_token()

Setter/getter for the API token

=cut

sub access_token {
    my $self = shift;
    if ( my $token = shift ) {
        $self->{'access_token'} = $token;
    }
    return $self->{'access_token'};
}

=head2 is_product_licensed()

Returns a boolean value indicating whether the product is licensed on this
server according to the cPanel license server; it ultimately checks against
what is listed in the cpanel.lisc file.

=cut

sub is_product_licensed {
    my ( $self, %args ) = @_;

    if ( exists $args{cache} && !$args{cache} ) {
        Whostmgr::API::1::Utils::Execute::execute_or_die( 'Sys', 'run_cpkeyclt' );
    }

    my $cplisc_id = $self->CPLISC_ID();

    return Cpanel::Server::Type::is_licensed_for_product($cplisc_id);
}

=head2 is_product_installed()

Returns a boolean value indicating whether the product is installed on
this server.

The default implementation of C<is_product_installed> does the check by
looking to see whether the RPM name from the C<RPM_NAME> attribute is
installed. If you need a different type of check, you can override the
C<is_product_installed> method itself.

=cut

sub is_product_installed {
    my ($self) = @_;

    return Cpanel::Pkgr::is_installed( $self->RPM_NAME ) ? 1 : 0;
}

=head2 get_product_price()

Looks up the current price of the product license for this server and
returns it as a US dollar value (without currency symbol). This price can
vary depending on the cPanel & WHM license type.

If price information is not available, the returned value will be undefined.

=cut

sub get_product_price {
    my ($self) = @_;
    my $product = $self->get_product();
    return $product->{price};
}

=head2 get_product_id()

Returns the item_id number from the cPanel store.  This is needed to create
the checkout for the Solo or Unlimited license.

=cut

sub get_product_id {
    my ($self) = @_;
    my $product = $self->get_product();
    return $product->{item_id};
}

=head2 get_product()

Returns the Store information on this product. This is used internally by
other methods.

This returns a single entry from the list of entries returned by the Store
API. For additional detail on the structure of this response, see:

  https://cpanel.wiki/display/SDI/Store+API+Functions+-+Get+the+cPanel+Store+Products+List

If the correct item id is not found in the store listings, an exception will be thrown.

=cut

sub get_product {
    my ($self) = @_;

    my $store        = Cpanel::cPStore->new();
    my $product_list = $store->get('products/cpstore');

    my $is_cpanel_solo = ( Cpanel::Server::Type::get_max_users() == 1 );

    my $product_id =
        $is_cpanel_solo
      ? $self->STORE_ID_SOLO()
      : $self->STORE_ID_UNLIMITED();

    foreach my $product (@$product_list) {
        return $product if $product->{'item_id'} == $product_id;
    }

    die lh()->maketext( 'The system failed to find a product with the identifier “[_1]” in the [asis,cPanel Store].', $product_id );
}

=head2 get_manage2_data(PRODUCT)

=head3 ARGUMENTS

=over

=item PRODUCT - string

The name of a <product>.cgi script on manage2 used to check if the partner
the current account belongs to has disabled the specific product.

If something goes wrong while querying manage2, defaults to allow the
product for the user.

=back

=head3 RETURNS

hashref with the following properties:

=over

=item disabled - Boolean

1 if the product is disabled by the partner, 0 otherwise

=item url - String

not used

=item email - String

not used

=back

=cut

sub get_manage2_data {
    my ( $self, $product ) = @_;

    my $url = sprintf( '%s/%s.cgi', Cpanel::Config::Sources::get_source('MANAGE2_URL'), $product );

    my $raw_resp = eval {
        my $http = Cpanel::HTTP::Client->new( timeout => 10 )->die_on_http_error();
        $http->get($url);
    };

    # on error
    return { disabled => 0, url => '', email => '' } if $@ or not $raw_resp;

    my $json_resp;
    if ( $raw_resp->success ) {
        $json_resp = eval { Cpanel::JSON::Load( $raw_resp->content ) };

        if ( my $exception = $@ ) {
            print STDERR $exception;
            $json_resp = { disabled => 0, url => '', email => '' };
        }
    }
    else {
        $json_resp = { disabled => 0, url => '', email => '' };
    }

    return $json_resp;
}

=head2 get_custom_url()

Returns the product custom url from Manage2.

=cut

sub get_custom_url {
    my ($self) = @_;

    return $self->get_manage2_data( $self->MANAGE2_PRODUCT_NAME )->{'url'};
}

sub _write_install_handshake_log {
    my %args = @_;
    my ( $file_path, $error, $success_detail ) = @args{qw(file_path error success_detail)};
    my $json;
    if ($error) {
        $json = Cpanel::JSON::Dump( { ok => 0, message => $error } );
    }
    else {
        $json = Cpanel::JSON::Dump( { ok => 1, message => $success_detail || '' } );
    }
    Cpanel::FileUtils::Write::overwrite( $file_path, $json, 0600 );
    return;
}

=head2 os_supported()

Returns a boolean indicating whether the current OS is supported by the
product. This is based on the IS_AVAILABLE_ON_THIS_OS provided in
your implementation class. It is recommended you use a Cpanel::OS
question to answer this in your class.

=cut

sub os_supported {
    my ($self) = @_;
    return $self->IS_AVAILABLE_ON_THIS_OS ? 1 : 0;
}

=head2 server_type_supported()

Returns a boolean indicating whether the server type is supported by the
product. This is based on the SERVER_AVAILABILITY information provided in
the implementation class. Alternatively, you may override this method in
your implementation if you have specific rules to apply that don't fit the
predefined criteria.

=cut

sub server_type_supported {
    my ($self) = @_;

    my $availability = $self->SERVER_TYPE_AVAILABILITY;
    my $server_type  = $self->server_type;
    return $availability->{$server_type};
}

=head2 server_type()

Returns the server type. The possible values are:

=over

=item * standard - A regular, non-virtualized server

=item * vm - A virtual machine

=item * container - A container environment

=back

=cut

sub server_type {
    my ($self) = @_;

    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => '/usr/local/cpanel/bin/envtype',
    );
    chomp( my $server_type = $run->stdout );

    return 'standard' if $server_type eq 'standard';

    return 'container' if grep { $server_type eq $_ } qw(
      virtuozzo
      vzcontainer
      virtualiron
      lxc
      vserver
    );

    return 'vm';
}

=head2 host_license_type_supported()

Returns a boolean indicating whether the cPanel server's license type is
supported by the product.  This is based on the HOST_LICENSE_TYPE_AVAILABILITY
information provided in the implementation class.  Alternatively, you may
override this method in your implementation if you have specific rules to
apply that don't fit the predefined criteria.

=cut

sub host_license_type_supported {
    my ($self) = @_;

    my $availability = $self->HOST_LICENSE_TYPE_AVAILABILITY;
    my $license_type = $self->host_license_type;
    return $availability->{$license_type};
}

=head2 host_license_type()

Returns the license type of the cPanel & WHM server. For the purposes of this method, the possible
values are:

=over

=item * unlimited - A regular cPanel & WHM license

=item * solo - A cPanel Solo license

=back

Currently no consideration is given to the possibility of other license
types. Anything other than 'solo' will be assumed to be 'unlimited'. If
other relevant license types become known, either update Store.pm's
server_type method to consider more than just these two, or override it
in your implementation to suit your specific needs. For example, you could
update it to also be aware of DNSONLY, server profile, etc.

=cut

sub host_license_type {
    my ($self) = @_;

    my $is_cpanel_solo = ( Cpanel::Server::Type::get_max_users() == 1 );
    return $is_cpanel_solo ? 'solo' : 'unlimited';
}

=head2 install()

Attempt to install the product without first checking whether it is already
installed.

=cut

sub install {
    my ($self) = @_;
    my $response_filename = $self->_response_file();

    my $daemon_pid = Cpanel::Daemonizer::Tiny::run_as_daemon(
        sub {
            eval {
                Cpanel::PIDFile->do(
                    $self->PID_FILE,
                    sub {
                        _unlink( $self->_response_file() );    # if we get the pid file, unlink any previous response to avoid reporting old outcomes
                        $self->install_implementation();
                    }
                );
            };

            if ( my $exception = $@ ) {
                if ( eval { $exception->isa('Cpanel::Exception::CommandAlreadyRunning') } ) {
                    my $logger = Cpanel::Logger->new();
                    my $pid    = $exception->get('pid');
                    $logger->info("Install already running (pid $pid). Waiting for the install to finish.");
                    $self->wait_for_daemon( $pid, 10 );
                }
                elsif ( eval { $exception->isa('Cpanel::Exception::Store::PartialSuccess') } ) {
                    my $detail = $exception->detail;
                    _write_install_handshake_log(
                        file_path      => $response_filename,
                        success_detail => $detail,
                    );
                }
                else {
                    # Something went wrong, but we could not handle it.
                    _write_install_handshake_log( file_path => $response_filename, error => Cpanel::Exception::get_string($exception) );
                    my $logger = Cpanel::Logger->new();
                    $logger->info( "Install failed with exception: " . Cpanel::Exception::get_string($exception) );
                    require Cpanel::Notify;
                    Cpanel::Notify::notification_class(
                        application      => 'Market',
                        interval         => 1,
                        status           => 'failure',
                        class            => 'Market::WHMPluginInstall',
                        constructor_args => [
                            product => $self->HUMAN_PRODUCT_NAME,
                            error   => $exception,
                            url     => $self->default_redirect_url(),
                        ],
                    );
                    die $exception;
                }
            }
            else {
                _write_install_handshake_log( file_path => $response_filename, error => '' );    # Success
            }
        }
    );

    if ( $self->wait_for_daemon( $daemon_pid, 10 ) ) {
        my $resp = _read_install_handshake_log($response_filename);
        if ( !$resp->{ok} ) {
            die $resp->{message};
        }

        return ( 1, $resp->{message} );
    }

    return ( 1, 'Did not wait' );
}

sub _read_install_handshake_log {
    my ($file_path) = @_;
    my $resp;
    return Cpanel::JSON::LoadFile($file_path);
}

=head2 wait_for_daemon(PID, INTERVAL)

Wait for the install process to finish.

The default behavior provided by Whostmgr::Store will be correct if you want to wait for the
install to finish when $obj->install is called. If you prefer to put the task into the background
or have some alternative waiting behavior, you may override this method.

The return value should indicate whether waiting happened or not. If you choose not to wait for
the install, you must return a false value. Exception: It is OK to return true if a timeout occurred.

=cut

sub wait_for_daemon {
    my ( $self, $pid, $interval ) = @_;
    my $alive;
    my $t0 = time();
    do {
        $alive = kill( 0, $pid );
        _sleep($interval);
    } while ( $alive > 0 && time() - $t0 < 86400 );
    return 1;
}

sub _print {
    my ( $self, $to_print ) = @_;
    return print $to_print;
}

=head2 return_to_security_advisor(DELAY)

Redirects back to the Security Advisor in WHM. This may be useful if your
product purchase is being set up from the Security Advisor. In other cases,
this is not needed.

=over

=item DELAY - Number - (Optional) The number of seconds to wait before
redirecting instead of the default

=back

=cut

sub return_to_security_advisor {
    my ( $self, $delay ) = @_;
    my $path                 = q{cgi/securityadvisor/index.cgi};
    my $security_advisor_url = $self->build_redirect_url($path);
    return $self->_refresh( $security_advisor_url, $delay );
}

sub _refresh {
    goto &refresh;
}

=head2 refresh(URL, DELAY)

Prints a meta http-equiv="refresh" tag to stdout to redirect to URL after
a DELAY-second delay (defaults to 5 seconds if DELAY not specified).

=cut

sub refresh {
    my ( $self, $url, $delay ) = @_;
    my $REFRESH_DELAY = 5;
    $delay = ( defined $delay ) ? int $delay : $REFRESH_DELAY;

    return if $self->fix_url_and_refresh( $url, $delay );

    $url = Cpanel::Encoder::Tiny::safe_html_encode_str($url);

    my $nonce = "bogus";
    require Cpanel::Config::LoadCpConf;
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    if ( $cpconf->{csp} ) {
        require Cpanel::CSP::Nonces;
        my $noncer = Cpanel::CSP::Nonces->instance();
        $nonce = $noncer->nonce();
    }

    return $self->_print(
        qq{
        <script type="text/javascript" src="https://www.google-analytics.com/analytics.js" nonce="$nonce"></script>
        <script>
        window.ga=window.ga||function(){(ga.q=ga.q||[]).push(arguments)};ga.l=+new Date;
        ga('create', 'UA-117050492-1', 'auto');
        ga('send', 'pageview');
        </script>
        <meta http-equiv="refresh" content="$delay; url=$url" />
        </head>
        <body>
        Please wait, redirecting...
        </body>
        </html>
    }
    );
}

=head2 fix_url_and_refresh(URL, DELAY)

The cPanel store tends to mangle query strings.  This de-mangles them and refreshes you to a page with the parameters corrected.
If nothing needs correcting, it simply short-circuits.

Returns 0 when we short-circuit, 1 when we fix.

=cut

sub fix_url_and_refresh {
    my ( $self, $url, $delay ) = @_;
    my $REFRESH_DELAY = 5;
    $delay = ( defined $delay ) ? int $delay : $REFRESH_DELAY;

    #Strip queries from redirect uri, fix &
    $url =~ s/%3F/\?/g;
    $url =~ s/%23/&/g;
    $url =~ s/&amp;/&/g;
    my @url_fragments = split( /\?/, $url );
    my $baseurl       = shift @url_fragments;

    # If we have more than one URL fragment we either have double ? or parameters in redirect_uri, which are verboten.
    # We must redirect once more after fixing this.
    return 0 unless scalar( @url_fragments > 1 );

    $url = $baseurl;
    my %qs_parse;
    foreach my $frag ( map { Cpanel::Encoder::URI::uri_decode_str($_) } @url_fragments ) {
        my $frag_parse = Cpanel::HTTP::QueryString::parse_query_string_sr( \$frag );
        @qs_parse{ keys(%$frag_parse) } = map { Cpanel::Encoder::URI::uri_encode_str($_) } values(%$frag_parse);
    }

    my $qs = '';
    my @qs;

    # Oh how I wish we had reduce {}
    foreach my $key ( keys(%qs_parse) ) {
        push( @qs, "$key=$qs_parse{$key}" );
    }
    $qs  = "?" . join( '&', sort @qs ) if @qs;
    $url = Cpanel::Encoder::Tiny::safe_html_encode_str("$url$qs");

    $self->_print(qq{<meta http-equiv="refresh" content="$delay; url=$url" /></head><body>Please wait, redirecting...</body></html>});
    return 1;
}

sub _sleep {
    return sleep shift;
}

=head2 default_error_handler( error => ..., _at => ... )

=head3 Synopsis

    sub handle_error {
        my ($self, %args) = @_;
        $self->default_error_handler(%args);
    }

=head3 What it does

Three things:

=over

=item * Shows a product purchase error page with the exact error message

=item * Writes the error to the error log

=over

=item * If returning to the Security Advisor on failure is not the correct
behavior, then you must provide your own error handler instead of using
C<default_error_handler()>.

=back

=back

=cut

sub default_error_handler {
    my ( $self, %args ) = @_;
    my $logger = $self->{logger};
    my ( $error, $_at ) = @args{qw(error _at)};

    my $error_detail = ( split /\n/, $_at || '' )[0];
    chomp $error_detail if defined $error_detail;

    $logger->info( sprintf( "%s%s%s", $error, ($_at) ? q{: } : q{}, ($_at) ? $_at : q{} ) );

    require Cpanel::Template;
    Cpanel::Template::process_template(
        'whostmgr',
        {
            'template_file' => 'store/product_purchase_failed.tmpl',
            data            => {
                product      => $self->HUMAN_PRODUCT_NAME,
                error        => $error,
                error_detail => $error_detail,
                redirect_url => scalar( $self->default_redirect_url ),
            }
        },
    );

    return;
}

=head2 build_redirect_url( PATH )

Given PATH, which is the path portion of the URL to redirect to in WHM, builds
a complete URL that also includes the hostname, port, and security token.
The main functionality provided by this function is looking up the correct
protocol to use (http or https) based on the port number.

=cut

sub build_redirect_url {
    my ( $self, $path ) = @_;

    if ( !$self->{port} || !$self->{host} || !$self->{security_token} ) {
        die 'Whostmgr::Store must be used within a WHM session if a purchase is being made.';
    }

    my $port = $self->{'port'};

    my $service = $Cpanel::Services::Ports::PORTS{$port};
    die "Unknown port: $port\n" if !$service;

    $path =~ s{^/}{};    # Normalize input so we don't get a double slash below

    my %service_protocols = (
        whostmgr  => 'http',     # WHM no-SSL
        whostmgrs => 'https',    # WHM SSL
        cphttpd   => 'http',     # proxy subdomain no-SSL
        cphttpds  => 'https',    # proxy subdomain SSL
    );

    my $protocol = $service_protocols{$service} || die "Unexpected service: $service";

    my $app = '';
    $app = "_" . $self->whm_app() if $self->whm_app();

    require Whostmgr::GoogleAnalytics;
    my $utm_tags = Whostmgr::GoogleAnalytics::utm_tags( $ENV{HOST}, $self->whm_source(), "WHM$app" );

    return sprintf( "%s://%s:%s%s/%s%s", $protocol, $self->{'host'}, $port, $self->{'security_token'}, $path, $utm_tags );
}

sub whm_app {
    my ( $self, $app ) = @_;
    $self->{_whm_app} = $app if $app;
    return $self->{_whm_app};
}

sub whm_source {
    my ( $self, $source ) = @_;
    $self->{_source} = $source if $source;
    return $self->{_source};
}

=head2 default_redirect_url()

Returns the full default redirect URL based on the C<redirect_path> attribute passed into the constructor.
This is the destination for redirect upon completion. Note: There are other intermediate redirects that
also happen while the purchase/install is still being processed.

=cut

sub default_redirect_url {
    my ($self) = @_;

    return $self->build_redirect_url( $self->{redirect_path} );
}

=head2 logger()

If a C<logger> attribute was passed in during construction, this method retuns that instance.
This allows you to continue using a logger object with a custom path. If no C<logger> attribute
was passed in, a new generic one will be created.

=cut

sub logger {
    my ($self) = @_;

    my $logger = $self->{logger} || Cpanel::Logger->new();

    return $logger;
}

=head2 purchaselink(STRING suffix)

Provide the proper link to purchase the product depending on partner overrides.

PURCHASE_START_URL and MANAGE2_PRODUCT_NAME must be correct in the subclass for this to work.

If SUFFIX is provided, the default WHM url will be suffixed like so: $url_$suffix.

Generally the suffix will correspond to an APPKEY in whm denoting the origin of the request.

=cut

sub purchaselink {
    my ( $self, $suffix ) = @_;
    $suffix ||= '';
    $suffix = '_' . $suffix if $suffix;

    # Check if the partner has overridden this to go somewhere else, and if not, provide cPstore redirect
    my $partner_data = $self->get_manage2_data( $self->MANAGE2_PRODUCT_NAME );
    my $override     = ref $partner_data eq 'HASH' ? $partner_data->{url} : '';
    my $default      = $self->PURCHASE_START_URL . $suffix;
    return $override ? $override : $default;
}

sub _installer_tempfile {
    my $temp = File::Temp->new();
    my $file = $temp->filename();
    return ( $temp, $file );
}

sub _response_file {
    my ($self) = @_;
    return sprintf( '/var/run/store-%s-install-response.json', $self->_product_slug );
}

sub _product_slug {
    my ($self) = @_;
    my $name = $self->HUMAN_PRODUCT_NAME;
    $name =~ s/[^a-zA-Z0-9\+]/_/g;
    return $name;
}

sub _unlink {
    return Cpanel::Autowarn::unlink(shift);
}

=head1 EXAMPLE IMPLEMENTATION

    package Whostmgr::ExampleProduct;

    use base 'Whostmgr::Store';

    # You may need to work with a team from SDI to determine the correct values to use here
    # for the license system, Store, and Manage2.

    # License system
    use constant PRODUCT_ID                => 'ExampleProduct';
    use constant PACKAGE_ID_RE             => qr/-EXAMPLEPRODUCT-/;
    use constant CPLISC_ID                 => 'exampleproduct';

    # Store
    use constant STORE_ID_UNLIMITED => 100, # ExampleProduct monthly unlimited
    use constant STORE_ID_SOLO      => 101, # ExampleProduct monthly solo

    # Manage2
    use constant MANAGE2_PRODUCT_NAME      => 'exampleproduct';

    # Other
    use constant RPM_NAME                  => 'exampleproduct';
    use constant INSTALL_GET_URL           => 'https://example.com/ExampleProduct.sh';
    use constant PID_FILE                  => '/var/run/store-exampleproduct-install-running';
    use constant LOG_FILE                  => '/path/to/log';
    use constant PURCHASE_START_URL        => 'scripts13/buy_a_dog';

    # You should use or come up with a Cpanel::OS question specific to this product.
    sub IS_AVAILABLE_ON_THIS_OS { return Cpanel::OS::can_do_a_thing() }

    # All of these are set to false in the example. Update some or all to true according to which
    # server types your product supports.
    use constant SERVER_TYPE_AVAILABILITY => {
        standard  => 0,
        vm        => 0,
        container => 0,
    };

    # Both of these are set to false in the example. Update one or both to true according to which
    # cPanel & WHM license types your product supports.
    use constant HOST_LICENSE_TYPE_AVAILABILITY => {
        unlimited => 0,
        solo      => 0,
    };

    # There will probably be a bit more to your install_implementation method than you see here,
    # but this is a start. In this example, it assumes the file provided by INSTALL_GET_URL (using
    # get_installer) is a shell script. If it's something else, of course you'll need to use it
    # some other way.
    sub install_implementation {
        my ( $temp, $installer ) = $self->get_installer();

        Cpanel::SafeRun::Object->new_or_die(
            program    => '/bin/bash',
            args       => [$installer],
            after_fork => sub {
                $0 = 'Install ExampleProduct';
            },
            timeout => 30,
        );

        return;
    }

    sub handle_error {
        my ( $self, %args ) = @_;
        return $self->default_error_handler(%args);
    }

    # (Remember that you can also override methods from Whostmgr::Store if the default implementations
    # are not adequate for your module.)

    1;

=head1 SEE ALSO

=over

=item * Cpanel::cPStore - A lower-level module focused just on the Store
API. In comparison, Whostmgr::Store handles the complete purchase and
install process on a cPanel & WHM server, which goes beyond just calling
the Store API. (Cpanel::cPStore is used internally by Whostmgr::Store.)

=item * Cpanel::Market::Provider::cPStore - Another lower-level module
that provides access to the cPanel Store through the "market provider"
mechanism. This module is a combination of generic functionality and SSL/TLS
certificate purchase code. Some of the functionality in this module is
used by Whostmgr::Store. However, Whostmgr::Store has two main differences:
(1) Meant to cover the entire purchase and install process (2) Meant to be
completely generic and not include implementation-specific code.

=back

=cut

1;
