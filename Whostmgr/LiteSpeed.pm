package Whostmgr::LiteSpeed;

# cpanel - Whostmgr/LiteSpeed.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use JSON::XS                          ();
use Cpanel::DIp::LicensedIP           ();
use Cpanel::Config::Sources           ();
use Cpanel::cPStore                   ();
use Cpanel::Market::Provider::cPStore ();
use Cpanel::Encoder::Tiny             ();
use Cpanel::HTTP::Client              ();
use Cpanel::TempFile                  ();
use Cpanel::SafeRun::Object           ();
use Cpanel::PasswdStrength::Generate  ();
use Cpanel::Locale                    ();

our $REFRESH_DELAY             = 8;                                                                 # seconds
our $LITESPEED_INSTALL_URL     = q{https://www.litespeedtech.com/packages/cpanel};
our $LITESPEED_INSTALL_SCRIPT  = q{lsws_whm_autoinstaller.sh};
our $LITESPEED_INSTALL_GET_URL = qq{$LITESPEED_INSTALL_URL/$LITESPEED_INSTALL_SCRIPT};
our $LITESPEED_INSTALL_TIMEOUT = 180;
our $LITESPEED_CGI_RELATIVE    = 'cgi/lsws/lsws.cgi';
our $LITESPEED_CGI             = '/usr/local/cpanel/whostmgr/docroot/' . $LITESPEED_CGI_RELATIVE;
our $LITESPEED_DIR             = '/usr/local/lsws/admin';
our $LITESPEED_BASE_DIR        = '/usr/local/lsws';
our $LITESPEED_BIN_RELATIVE    = 'bin/lshttpd';
our $LITESPEED_CMDSH           = '/usr/local/cpanel/whostmgr/docroot/cgi/lsws/bin/lsws_cmd.sh';

sub new {
    my $pkg  = shift;
    my $self = {
        'access_token' => undef,
    };
    bless $self, $pkg;
    return $self;
}

sub get_login_url {
    my ( $self, $args_hr ) = @_;

    # create refresh url to handle OAuth2 login callback (on authentication)
    my $refresh_url = sprintf( "https://%s:%s%s/%s?license_type=%s", $args_hr->{'host'}, $args_hr->{'port'}, $args_hr->{'security_token'}, $args_hr->{'path'}, $args_hr->{'license_type'} );

    # return url to user uses to authenticate OAuth2 token
    my $login_url = Cpanel::cPStore::LOGIN_URI($refresh_url);
    return $login_url;
}

sub validate_login_token {
    my ( $self, $args_hr ) = @_;

    # create refresh url to handle OAuth2 login callback (on authentication)
    my $refresh_url = sprintf( "https://%s:%s%s/%s?license_type=%s", $args_hr->{'host'}, $args_hr->{'port'}, $args_hr->{'security_token'}, $args_hr->{'path'}, $args_hr->{'license_type'} );

    local $@;
    my $response = eval { Cpanel::cPStore::validate_login_token( $args_hr->{'code'}, $refresh_url ) };

    die $@ if $@;    # throw error to caller

    if ( $response->{'token'} ) {
        $self->access_token( $response->{'token'} );
    }
    return $self->access_token();
}

sub create_shopping_cart {
    my ( $self, $args_hr ) = @_;
    my $refresh_url = sprintf( "https://%s:%s%s/%s", $args_hr->{'host'}, $args_hr->{'port'}, $args_hr->{'security_token'}, $args_hr->{'path'} );
    local $@;
    my ( $order_id, $order_items_ref ) = eval {
        Cpanel::Market::Provider::cPStore::create_shopping_cart(
            access_token       => $self->access_token(),
            url_after_checkout => $refresh_url,
            items              => [
                {
                    'product_id' => $self->get_litespeed_product_id( $args_hr->{'license_type'} ),
                    'ips'        => [ Cpanel::DIp::LicensedIP::get_license_ip() ],
                }
            ],
        );
    };

    # Catch any known errors and present with some relevant detail to the user
    if ( my $error = $@ ) {

        # Just die if it isn't an object
        if ( !eval { $error->isa('Cpanel::Exception') } ) {

            # Note that localizing this only to die immediately after is
            # somewhat pointless, but cplint requests it. Do it as such.
            local $@ = $error;
            die;
        }
        my $error_string = $error->get_string();
        if ( $error_string =~ m/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}) has an existing license/ ) {
            die "$1 already has a similar license. Contact Customer Support if you wish to change your license type.\n";
        }
        elsif ( $error_string =~ m/ You have an active license for (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/ ) {
            die "$1 already has the same license that you want to purchase. Contact Customer Support if you wish to change your license type.\n";
        }
        elsif ( $error_string =~ m/Package \'\d+\' is not allowed for company \'(.+)\'\./ ) {
            die "You authenticated to the cPanel Store with a partner account, “$1”. This account does not qualify to buy this license from the cPanel Store.\n";
        }
    }

    my $checkout_url = Cpanel::cPStore::CHECKOUT_URI_WHM($order_id);
    return ( $order_id, $order_items_ref, $checkout_url );
}

sub access_token {
    my ( $self, $token ) = @_;
    if ($token) {
        $self->{'access_token'} = $token;
    }
    return $self->{'access_token'};
}

sub get_litespeed_product_id {
    my ( $self, $code ) = @_;

    my %mapping = (

        # Legacy
        'vps' => 'LiteSpeed VPS',
        'ded' => 'LiteSpeed Dedicated',

        # Supported
        'unlimited' => 'LiteSpeed UNLIMITED',
        '8gb'       => 'LiteSpeed 8GB'
    );

    my $display_name = $mapping{$code};

    if ( not defined $display_name ) {
        die "Invalid license type. Must be 'unlimited' or '8gb'.\n";
    }

    my $pkg_list_ar = get_all_available_store_packages();
    my $item_id;
    foreach my $package ( @{$pkg_list_ar} ) {
        $item_id = $package->{'item_id'} if $package->{'display_name'} eq $display_name;
    }
    return $item_id;
}

sub _verify_litespeed_license {
    my $self         = shift;
    my $mainserverip = Cpanel::DIp::LicensedIP::get_license_ip();
    my $verify_url   = sprintf( "%s/api/ipaddrs?ip=%s", Cpanel::Config::Sources::get_source('VERIFY_URL'), $mainserverip );
    local $@;
    my $response = eval {
        my $http = Cpanel::HTTP::Client->new()->die_on_http_error();
        $http->get($verify_url);
    };
    die $@ if $@;

    my $results = eval { JSON::XS::decode_json( $response->{'content'} ) };
    die $@ if $@;

    my $verified = 0;
    foreach my $current ( @{ $results->{'current'} } ) {

        if ( $current->{'product'} eq q{LiteSpeed} and $current->{'status'} eq 1 and $current->{'valid'} eq 1 ) {
            ++$verified;
            last;
        }
    }
    return $verified;
}

# TODO: This doesn't really try to ~find~ it. Not sure where else it would be on Centos boxes anyway.
sub _find_bash_bin {
    for my $path (qw ( /bin/bash )) {
        if ( -x $path ) {
            return $path;
        }
    }
    return undef;
}

sub get_litespeed_license {
    my ($self) = @_;
    if ( $< != 0 ) {
        return ( 0, "You must be root to call this function" );
    }
    require Whostmgr::Store::Addons;
    my $license_handler = Whostmgr::Store::Addons->new();
    my ( $rc, $results ) = $license_handler->get_license_with_cache();

    if ( $rc && defined $results ) {
        if ( defined $results->{'active'} ) {

            # Iterate through each of the active licenses to find out LiteSpeed one and get it's license key / serial
            foreach my $active_license_ar ( @{ $results->{'active'} } ) {
                if ( defined $active_license_ar->{'product'} ) {
                    if ( $active_license_ar->{'product'} eq 'LiteSpeed' ) {
                        if ( defined $active_license_ar->{'serial'} ) {

                            # Defensive check to make sure the serial looks valid, rather than 'N/A' or something
                            if ( $active_license_ar->{'serial'} =~ m/.+\-.+\-.+\-.+/ ) {
                                return ( 1, $active_license_ar->{'serial'} );
                            }
                        }
                    }
                }
            }
        }
        else {
            return ( 0, "No active license found for LiteSpeed" );
        }
    }
    return ( 0, "No active license found for LiteSpeed" );
}

sub install_litespeed {
    my ( $self, $args ) = @_;

    my $temp_gen_pass = Cpanel::PasswdStrength::Generate::generate_password(
        12,                      # 12 char long pass. The following 2 args limit it to 0-9a-zA-Z
        no_symbols      => 1,    # Prevent anything else that might need to be escaped. This is a temporary pass only used to get the admin logged in to the LiteSpeed cnotrol panel the first time
        no_othersymbols => 1,    # Prevent #"'; from being included.
    );

    # Check that your kit is complete
    $args->{'license_key'} ||= 'TRIAL';
    $args->{'admin_user'}  ||= 'admin';
    $args->{'admin_pass'}  ||= $temp_gen_pass;
    $args->{'admin_email'} ||= 'root@localhost';    # TODO: take this from CONTACTEMAIL in /etc/wwwacct.conf ?

    # TODO Set $php_suexec to whether suexec is enabled for the system????
    my ( $php_suexec, $port_offset, $integrate_with_ea, $auto_switch_to_lsws ) = qw{2 0 1 1};

    # get script from $LITESPEED_INSTALL_GET_URL
    local $@;
    my $response = eval {
        my $http = Cpanel::HTTP::Client->new()->die_on_http_error();    # We require the upstream installer URL to have a valid SSL cert as no cpsources.conf override exists for it yet (or should)
        $http->get($LITESPEED_INSTALL_GET_URL);
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

    # TODO: Make sure we tell the user the random pass we created for them so they can log in, luckily changing the admin pass is documented in the LSWS and is an easy one liner on the shell
    my $run_args = [
        $filename,             $args->{'license_key'}, $php_suexec,        $port_offset, $args->{'admin_user'},
        $args->{'admin_pass'}, $args->{'admin_email'}, $integrate_with_ea, $auto_switch_to_lsws,
    ];

    # execute $filename to install, log to STDOUT/STDIN, as the API will already be capturing this output and redirecting it.
    if ( defined( $ENV{'SERVER_PROTOCOL'} ) ) {
        my $locale = Cpanel::Locale->get_handle();

        print $locale->maketext("Record this login information for your records.") . "<br>\n";
        print $locale->maketext( "Admin Username: [output,strong,_1]", $args->{'admin_user'} );
        print "<br>\n";
        print $locale->maketext( "Admin Password: [output,strong,_1]", $args->{'admin_pass'} );
        print "<br><br><pre id='litespeedInstallation' style='max-width:800px; max-height:480px'>\n";
        print <<EOJS;
        <script>
        function litespeedInstallScroll () {
            var installEl = document.getElementById("litespeedInstallation");
            var scrollEnd;
            if(installEl.scrollHeight > installEl.clientHeight) {
                scrollEnd = installEl.scrollHeight;
                installEl.scroll(0, scrollEnd);
            }
        }
        </script>
        <!-- STARTING INSTALL-->
        <script>var intervalID = window.setInterval(litespeedInstallScroll, 100);
            function endScrollWatch() {1
            window.clearInterval(intervalID);
        }
        </script>
EOJS
    }
    my $run = Cpanel::SafeRun::Object->new(
        program => $bash_bin,
        args    => $run_args,
        timeout => $LITESPEED_INSTALL_TIMEOUT,
        stdout  => \*STDOUT,
        stderr  => \*STDOUT,
    );
    if ( defined( $ENV{'SERVER_PROTOCOL'} ) ) {
        print "</pre>\n";
        print "<script>window.setTimeout(endScrollWatch, 500);</script>\n";
    }

    die $run->autopsy() if $run->CHILD_ERROR();

    return 1;
}

sub is_litespeed_installed {

    # LiteSpeed's uninstaller script leaves lsws.cgi hanging around, so check for the admin dir too
    return -f $LITESPEED_CGI && -d $LITESPEED_DIR;
}

sub ensure_litespeed_installed {
    my ( $self, $args ) = @_;

    # LiteSpeed already installed
    if ( is_litespeed_installed() ) {
        return 1;
    }

    # need to install it
    # **NOTE** how we install it currently depends on the stakeholders. We'll likely just do a full replacement install
    return $self->install_litespeed($args);
}

sub get_button {
    my ( $self, $url, $btn_text ) = @_;
    return "<form action='$url' method='post'><button class='btn btn-primary' type='submit'>" . $btn_text . "</button></form>";
}

sub return_to_ea4 {
    my ( $self, $host, $port, $security_token, $delay ) = @_;
    my $path    = q{scripts7/EasyApache4};
    my $ea4_url = sprintf( "https://%s:%s%s/%s", $host, $port, $security_token, $path );

    # When the delay is less than zero, display a button to go back once they are ready
    if ( $delay < 0 ) {
        my $locale = Cpanel::Locale->get_handle();
        print $self->get_button( $ea4_url, $locale->maketext("Continue to [asis,EasyApache]") );
        return;
    }
    return $self->_refresh( $ea4_url, $delay );
}

sub build_lsws_url {
    my ( $self, $host, $port, $security_token ) = @_;
    return sprintf( "https://%s:%s%s/%s", $host, $port, $security_token, $LITESPEED_CGI_RELATIVE );
}

sub return_to_litespeed_plugin {
    my ( $self, $host, $port, $security_token, $delay ) = @_;
    my $lsws_url = build_lsws_url( $self, $host, $port, $security_token );
    return $self->_refresh( $lsws_url, $delay );
}

sub _refresh {
    my ( $self, $url, $delay ) = @_;
    $url   = Cpanel::Encoder::Tiny::safe_html_encode_str($url);
    $delay = ( defined $delay ) ? int $delay : $REFRESH_DELAY;
    return print qq{<meta http-equiv="refresh" content="$delay; url=$url" />};
}

# Display error then redirect user to the EA4 page to start over or do something else
sub _handle_litespeed_error {
    my ( $self, $args_hr ) = @_;
    my $delay = $REFRESH_DELAY;
    if ( defined( $args_hr->{'delay'} ) ) {
        $delay = $args_hr->{'delay'};
    }
    my $logger = $args_hr->{'logger'};
    if ( defined( $ENV{'SERVER_PROTOCOL'} ) ) {
        print( sprintf( "%s%s", '<div class="callout callout-info" style="max-width:800px;overflow:auto" aria-label="info">' . $args_hr->{'error'} . '</div>', ( $args_hr->{'_at'} ) ? q{<div class="callout callout-danger" style="max-width:800px;overflow:auto;" aria-label="danger">} . $args_hr->{'_at'} . q{</div>} : q{} ) );
    }
    $logger->warn( sprintf( "%s%s%s", $args_hr->{'error'}, ( $args_hr->{'_at'} ) ? q{ } : q{}, ( $args_hr->{'_at'} ) ? $args_hr->{'_at'} : q{} ) );
    return $self->return_to_ea4( $args_hr->{'host'}, $args_hr->{'port'}, $args_hr->{'security_token'}, $delay );
}

# Determines if we should be showing the LiteSpeed options anywhere in the UI.
# Currently called by whostmgr7
# See HB-4597 for details
sub show_litespeed {

    # LiteSpeed already installed, so the links serve no use. # TODO - change this to show a link to LSWS plugin page instead ?
    if ( is_litespeed_installed() ) {
        return 0;
    }

    # If we already have a LiteSpeed license, the links will give an error as such after a couple steps. # TODO - change the link, if LS is not installed but they have a license, to the installer url, skipping checkout steps
    my $handler = Whostmgr::LiteSpeed->new();
    my ( $rc, undef ) = $handler->get_litespeed_license();
    if ( defined $rc && $rc == 1 ) {
        return 0;
    }

    # If we don't see any LiteSpeed package available from the server's store, don't show the links
    my $found_ls_pkg = 0;
    my $pkg_list_ar  = get_all_available_store_packages();
    foreach my $package ( @{$pkg_list_ar} ) {
        if ( $package->{'display_name'} =~ /litespeed/i ) {
            $found_ls_pkg++;
        }
    }
    if ( $found_ls_pkg == 0 ) {
        return 0;
    }

    # If this server is under a partner and they have disabled LiteSpeed in manage2, don't show it
    my $advertising_preference = eval { get_company_advertising_preferences() };
    if ( exists $advertising_preference->{'disabled'} and $advertising_preference->{'disabled'} == 1 ) {
        return 0;
    }

    # Otherwise, if LS isn't already installed, and it doesn't already have a license, and it's showing in the store, and the license "company" hasn't disabled it, show the links
    return 1;
}

sub get_all_available_store_packages {
    my $package_list = [];
    eval {
        my $store = Cpanel::cPStore->new();
        $package_list = $store->get('products/cpstore');
    };
    return $package_list;
}

# Copied from KernelCare
sub get_company_advertising_preferences {
    require Cpanel::License::CompanyID;
    require Cpanel::JSON;
    require Cpanel::Exception;

    my $id = Cpanel::License::CompanyID::get_company_id();
    chomp $id if defined $id;

    die Cpanel::Exception->create("Cannot determine company ID.") if !$id;
    die Cpanel::Exception->create("Invalid company ID.")          if $id !~ m/^\d+$/;

    my $URL = sprintf( '%s/litespeed.cgi?companyid=%s', Cpanel::Config::Sources::get_source('MANAGE2_URL'), $id );

    my $client   = Cpanel::HTTP::Client->new( timeout => 20 )->die_on_http_error();
    my $response = $client->get($URL);

    die Cpanel::Exception::create('HTTP') if !$response->{success};

    return Cpanel::JSON::Load( $response->{content} );
}

# Shortcut to the commands in lsws_cmd.sh
sub lsws_cmd {
    my ( $self, $operation, @cmd_args ) = @_;

    my $cmd = Cpanel::SafeRun::Object->new(
        'program'      => $LITESPEED_CMDSH,
        'args'         => [ "$LITESPEED_BASE_DIR", $operation, @cmd_args ],
        'keep_env'     => 0,
        'timeout'      => (600),                                              # 10 minutes
        'read_timeout' => (600),
    );
    if ( !$cmd ) {
        return ( 0, '', "The command failed to run: $!" );
    }
    elsif ( $cmd->error_code() ) {
        return ( 0, $cmd->stdout, $cmd->stderr );
    }
    return ( 1, $cmd->stdout, $cmd->stderr );
}

sub ensure_using_latest_license {
    my ( $self, $serial_no ) = @_;
    if ( !$serial_no ) {
        return ( 0, 'This call requires the license key serial number as an argument', '' );
    }
    my $cmd = Cpanel::SafeRun::Object->new(
        'program'      => $LITESPEED_BASE_DIR . '/' . $LITESPEED_BIN_RELATIVE,
        'args'         => ['-V'],
        'keep_env'     => 0,
        'timeout'      => (60),                                                  # 1 minute
        'read_timeout' => (60),
    );

    # There are the two known license type responses, a leased license and an owned license. According to LS, any [OK] means a valid license, and the trial type is the only unpaid one.
    # [OK] Leased license key 2 will expire in 37 days!
    # [OK] License key #4 verification passed! Software upgrade expires in 2976 days.
    # [OK] Your trial license key will expire in 14 days!

    my $need_to_switch_to_new_license = 0;
    if ( $cmd->stderr =~ m/^\[ERROR\]/ ) {
        $need_to_switch_to_new_license = 1;
    }
    elsif ( $cmd->stdout =~ m/^\[OK\].*trial/ ) {
        $need_to_switch_to_new_license = 1;
    }
    elsif ( $cmd->stdout =~ m/^\[OK\]/ ) {
        return ( 2, "Valid license currently installed", '' );
    }

    if ( $need_to_switch_to_new_license == 1 ) {
        my $switch_license_cmd = Cpanel::SafeRun::Object->new(
            'program'      => $LITESPEED_CMDSH,
            'args'         => [ "$LITESPEED_BASE_DIR", 'CHANGE_LICENSE', $serial_no ],
            'keep_env'     => 0,
            'timeout'      => (600),                                                     # 10 minutes
            'read_timeout' => (600),
        );
        if ( $switch_license_cmd->stdout =~ m/Successfully switched to the new license/ ) {
            return ( 1, $switch_license_cmd->stdout, $switch_license_cmd->stderr );
        }
        else {
            return ( 0, $switch_license_cmd->stdout, $switch_license_cmd->stderr );
        }
    }
    else {
        return ( 0, "Valid license currently installed", '' );
    }
}

1;

# TODO: update all the pod once all conversions/changes have been made to support LiteSpeed
__END__

=head1 NAME

Whostmgr::LiteSpeed - encapsulates much of the behavior related to the purchase and installation of LiteSpeed through WHM

=head1 SYNOPSIS

  my $handler = Whostmgr::LiteSpeed->new();

  #... see whostmgr/bin/whostmgr12.pl for main use of this module

=head1 DESCRIPTION

This module was created to manage the implementation of the LiteSpeed purchase and installation
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

=item get_litespeed_product_id

Makes a call to the cPanel Store to determine the actual product_ids used by the monthly LiteSpeed VPS or Dedicated licenses

=item ensure_litespeed_installed

Manages checking for and installing the LiteSpeed plugin and server upon successful purchase; the actual installation procedure
is encapsulated in the internal method, C<install_litespeed> (see below in L<INTERNAL METHODS>).

=item is_litespeed_installed

Simple check to ensure that lsws.cgi is a file and the admin directory exists (see $LITESPEED_DIR and $LITESPEED_CGI)

=item return_to_litespeed_plugin

Redirects back to WHM with the LiteSpeed plugin loaded as the main frame target

=item return_to_ea4

Redirects back to WHM with EasyApache 4 loaded as the main frame target

=item build_lsws_url

Takes in core components of the URL and returns the full thing based on server settings

=back

=head2 INTERNAL METHODS

=over 4

=item _verify_litespeed_license

Queries cPanel for licenses associated with the main server ip and checks to see if LiteSpeed is currently listed as an active and valid license

=item install_litespeed

Implements the installation process for LiteSpeed.

=item _refresh

Requires 1 parameter (refresh URL). Accepts a second optional parameter to set the refresh delay. Default is the value of the package variable C<$Whostmgr::LiteSpeed::REFRESH_DELAY>.

Delayed refresh via meta refresh tag, separated out for testing purposes.

=item _handle_litespeed_error

General error handler, used when $@ is detected or some other error needs to halt the LiteSpeed purchase process. Logs all errors.

=back

=head1 LICENSE AND COPYRIGHT

Copyright 2022, cPanel, L.L.C. All rights reserved.
