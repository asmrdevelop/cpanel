package Whostmgr::JetBackup;

# cpanel - Whostmgr/JetBackup.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use JSON::XS                          ();
use Cpanel::Config::Sources           ();
use Cpanel::cPStore                   ();
use Cpanel::Market::Provider::cPStore ();
use Cpanel::Encoder::Tiny             ();
use Cpanel::HTTP::Client              ();
use Cpanel::SafeRun::Object           ();
use Cpanel::Locale                    ();
use Cpanel::OS                        ();

our $REFRESH_DELAY             = 8;                                                                 # seconds
our $JETBACKUP_INSTALL_TIMEOUT = 180;
our $JETBACKUP_CGI_RELATIVE    = 'cgi/addons/jetbackup5/index.cgi';
our $JETBACKUP_CGI             = '/usr/local/cpanel/whostmgr/docroot/' . $JETBACKUP_CGI_RELATIVE;
our $JETBACKUP_DIR4            = '/usr/local/jetapps/var/lib/JetBackup';
our $JETBACKUP_DIR5            = '/usr/local/jetapps/var/lib/jetbackup';                            # JB5 changed to use lowercase dir
our $JETBACKUP_BASE_DIR        = '/usr/local/jetapps';
our $JETBACKUP_BIN             = '/usr/bin/jetbackup';
our $JETBACKUP_API_BIN         = '/usr/bin/jetbackupapi';
our $JETAPPS_BIN               = '/usr/bin/jetapps';

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
                    'product_id' => $self->get_jetbackup_product_id( $args_hr->{'license_type'} ),
                    'ips'        => [ $self->mainserverip() ],
                }
            ],
        );
    };

    # Catch any known errors and present with some relevant detail to the user
    if ( my $exception = $@ ) {
        require Cpanel::Exception;
        my $error_string = Cpanel::Exception::get_string($@);
        if ( $error_string =~ m/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}) has an existing license/ ) {
            die "$1 already has a similar license. Contact Customer Support if you wish to change your license type.\n";
        }
        elsif ( $error_string =~ m/ You have an active license for (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/ ) {
            die "$1 already has the same license that you want to purchase. Contact Customer Support if you wish to change your license type.\n";
        }
        else {
            die "An error occurred during cart creation: $error_string\n";
        }
    }
    else {
        die $@ if $@;    # throw error to caller
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

sub mainserverip {
    my ($self) = @_;
    if ( not $self->{'mainserverip'} ) {
        require Cpanel::NAT;
        require Cpanel::DIp::MainIP;
        $self->{'mainserverip'} = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );
    }
    return $self->{'mainserverip'};
}

# $license_type = 'std' , only option for now
sub get_jetbackup_product_id {
    my ( $self, $license_type ) = @_;
    my $display_name_match;

    # Two types of licenses available
    if ( $license_type eq 'std' ) {
        $display_name_match = 'JetBackup';
    }
    else {
        die "Invalid license type. Must be 'std'.\n";
    }
    my $pkg_list_ar = get_all_available_store_packages();
    my $item_id;
    foreach my $package ( @{$pkg_list_ar} ) {
        $item_id = $package->{'item_id'} if $package->{'display_name'} eq $display_name_match;
        last                             if $item_id;
    }
    return $item_id;
}

sub _verify_jetbackup_license {
    my ($self)       = @_;
    my $mainserverip = $self->mainserverip();
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

        if ( $current->{'package'} eq q{CPDIRECT-JETBACKUP-MONTHLY} and $current->{'product'} eq q{JetBackup} and $current->{'status'} eq 1 and $current->{'valid'} eq 1 ) {
            ++$verified;
            last;
        }
    }
    return $verified;
}

# TODO: This doesn't really try to ~find~ it. Not sure where else it would be on Centos boxes anyway.
sub _find_bash_bin {
    my ($self) = @_;
    for my $path (qw ( /bin/bash )) {
        if ( -x $path ) {
            return $path;
        }
    }
    return undef;
}

sub get_jetbackup_license {
    my ($self) = @_;
    if ( $< != 0 ) {
        return ( 0, "You must be root to call this function" );
    }
    require Whostmgr::Store::Addons;
    my $license_handler = Whostmgr::Store::Addons->new();
    my ( $rc, $results ) = $license_handler->get_license_with_cache();

    if ( $rc && defined $results ) {
        if ( defined $results->{'active'} ) {

            # Iterate through each of the active licenses to find out JetBackup one and get its license key / serial
            foreach my $active_license_ar ( @{ $results->{'active'} } ) {
                if ( defined $active_license_ar->{'product'} ) {
                    if ( $active_license_ar->{'product'} eq 'JetBackup' ) {
                        if ( defined $active_license_ar->{'serial'} ) {
                            return ( 1, $active_license_ar->{'serial'} );
                        }
                    }
                }
            }
        }
        else {
            return ( 0, "Could not find an active JetBackup license" );
        }
    }
    return ( 0, "Could not find an active JetBackup license" );
}

sub install_jetbackup {
    my ( $self, $args ) = @_;

    if ( defined( $ENV{'SERVER_PROTOCOL'} ) ) {

        print "<br><br><pre id='jetbackupInstallation' style='max-width:800px; max-height:480px'>\n";
        print <<EOJS;
        <script>

        var pageContainer = document.getElementById("contentContainer");
        var installationSpinner = document.createElement('i');
        installationSpinner.id = "jetbackupInstallationSpinner";
        installationSpinner.className = "fas fa-spinner fa-spin fa-2x";
        pageContainer.appendChild(installationSpinner);

        function jetbackupInstallScroll () {
            var installEl = document.getElementById("jetbackupInstallation");
            var scrollEnd;
            if(installEl.scrollHeight > installEl.clientHeight) {
                scrollEnd = installEl.scrollHeight;
                installEl.scroll(0, scrollEnd);
            }
        }
        </script>
        <!-- STARTING INSTALL-->
        <script>var intervalID = window.setInterval(jetbackupInstallScroll, 100);
            function endScrollWatch() {
                var pageContainer = document.getElementById("contentContainer");
                var installationSpinner = document.getElementById("jetbackupInstallationSpinner");
                pageContainer.removeChild(installationSpinner);
                window.clearInterval(intervalID);
        }
        </script>
EOJS
    }

    require Cpanel::PackMan;
    my $pm = Cpanel::PackMan->instance;

    # This is the most future-proof method of installing JetBackup according to the JetApps developers
    # - install JetApps repo
    # - clean the repo cache
    # - install the jetapps-cpanel plugin
    # - use the jetapps script to install JetBackup

    my $repo_previously_installed = 0;
    if ( $pm->is_installed('jetapps-repo') ) {
        $repo_previously_installed = 1;
        print "** The JetApps repository is already installed, skipping..\n\n";
    }
    else {
        print "** Installing JetApps repository\n\n";
        local $@;
        my $repo_pkg = Cpanel::OS::jetbackup_repo_pkg();
        if ( Cpanel::OS::package_manager() eq 'apt' ) {
            my $ok = install_jb_repo_deb($repo_pkg);
            if ( !$ok ) {
                print "Error encountered trying to install the JetApps repository\n";
                _end_html_output();
                return 0;
            }
        }
        else {
            eval { $pm->sys->install($repo_pkg); };
            if ($@) {
                if ( $@ =~ m/does not update installed package/ ) {

                    # It's already installed, carry on
                }
                else {
                    # Some other error came back
                    print "Error encountered trying to install the JetApps repository: $@\n";
                    _end_html_output();
                    return 0;
                }
            }
        }
    }

    {
        local $@;
        print "** Cleaning repository cache\n\n";
        eval { $pm->sys->clean(); };
        if ($@) {
            print "Error encountered trying to clean the repository cache: $@\n";
            _revert_install_changes( { repo_previously_installed => $repo_previously_installed, pm => $pm } );
            _end_html_output();
            return 0;
        }
    }

    my $jetapps_previously_installed = 0;
    if ( $pm->is_installed('jetapps-cpanel') ) {
        $jetapps_previously_installed = 1;
        print "** The JetApps package is already installed, skipping..\n\n";
    }
    else {
        print "** Installing JetApps for cPanel\n\n";
        local $@;

        if ( Cpanel::OS::package_manager() eq 'apt' ) {
            eval { $pm->sys->install('jetapps'); };
        }
        else {
            eval { $pm->sys->install( 'jetapps', '--disablerepo=*', '--enablerepo=jetapps,jetapps-stable' ); };
        }

        if ($@) {
            print "Error encountered trying to install the jetapps-cpanel package and dependencies: $@\n";
            _revert_install_changes( { repo_previously_installed => $repo_previously_installed, pm => $pm } );
            _end_html_output();
            return 0;
        }
    }

    my $jetbackup_previously_installed = 0;
    if ( $pm->is_installed('jetbackup') ) {
        $jetbackup_previously_installed = 1;
        print "** The JetBackup package is already installed, skipping..\n\n";
    }
    else {
        print "** Installing JetBackup for cPanel\n\n";

        my ( $rc, $stdout, $stderr ) = $self->jb_cmd( '--install', 'jetbackup5-cpanel', 'stable' );

        print $stdout;
        if ( $stdout =~ m/Log file\:\s+(\/.+\.log)/ ) {
            my $log_file = $1;
            if ( open( my $log_fh, '<', $log_file ) ) {
                while (<$log_fh>) {
                    print $_;
                }
                close($log_fh);
            }
        }

        if ( $rc == 1 ) {
            print "** JetBackup has been successfully installed. Click the button below to continue.\n\n";
        }
        else {
            print "Error encountered during JetBackup installation:\n$stdout\n$stderr";
            _revert_install_changes( { repo_previously_installed => $repo_previously_installed, jetapps_previously_installed => $jetapps_previously_installed, pm => $pm } );
            _end_html_output();
            return 0;
        }
    }
    _end_html_output();

    return 1;
}

# It'd be nice to use PackMan for this part, but the steps needed are pretty specific
sub install_jb_repo_deb {
    my ($repo_pkg) = @_;
    require Cpanel::TempFile;
    my $temp_dir      = Cpanel::TempFile::get_safe_tmpdir();
    my @url_parts     = split( /\//, $repo_pkg );
    my $deb_file_name = pop(@url_parts);
    print "Downloading file $deb_file_name for Ubuntu ( $repo_pkg -> $temp_dir )\n";
    $ENV{'LC_ALL'} //= 'C';
    local $@;
    require HTTP::Tiny;
    chdir $temp_dir;
    my $http  = HTTP::Tiny->new();
    my $resp1 = $http->mirror( $repo_pkg,                                        $temp_dir . '/' . $deb_file_name );
    my $resp2 = $http->mirror( 'https://repo.jetlicense.com/static/jetapps.asc', $temp_dir . '/' . 'jetapps.asc' );

    if ( !$resp1->{success} || !$resp2->{success} ) {
        return 0;
    }
    system 'apt-key', 'add', $temp_dir . '/' . 'jetapps.asc';
    my $cmd = Cpanel::SafeRun::Object->new(
        'program'      => '/usr/bin/dpkg',
        'args'         => [ '-i', $temp_dir . '/' . $deb_file_name ],
        'keep_env'     => 0,
        'timeout'      => (600),
        'read_timeout' => (600),
    );
    if ( !$cmd || $cmd->error_code() ) {
        return 0;
    }
    system 'apt-get', 'update';
    unlink $temp_dir . '/' . $deb_file_name;
    unlink $temp_dir . '/' . 'jetapps.asc';

    return 1;
}

# Attempt to roll back changes to the system in the event we encounter a fatal error during installation process
sub _revert_install_changes {
    my ($args_hr) = @_;
    my $pm = $args_hr->{'pm'};
    if ( defined( $args_hr->{'jetapps_previously_installed'} ) && $args_hr->{'jetapps_previously_installed'} != 1 ) {
        $pm->sys->uninstall('jetapps-cpanel');
    }
    if ( defined( $args_hr->{'repo_previously_installed'} ) && $args_hr->{'repo_previously_installed'} != 1 ) {
        $pm->sys->uninstall('jetapps-repo');
    }
    return;
}

# I don't like this, but I am expecting that it goes away when we modularize all these plugins
sub _end_html_output {
    if ( defined( $ENV{'SERVER_PROTOCOL'} ) ) {
        print "</pre>\n";
        print "<script>window.setTimeout(endScrollWatch, 500);</script>\n";
    }
    return;
}

sub is_jetbackup_installed {
    return -f $JETBACKUP_CGI && ( -d $JETBACKUP_DIR4 || -d $JETBACKUP_DIR5 );
}

sub ensure_jetbackup_installed {
    my ( $self, $args ) = @_;

    # if JetBackup already installed
    if ( is_jetbackup_installed() ) {
        return 1;
    }

    # Otherwise we need to install it
    return $self->install_jetbackup($args);
}

sub _get_button {
    my ( $self, $url, $btn_text ) = @_;
    return "<form action='$url' method='post'><button class='btn btn-primary' type='submit'>" . $btn_text . "</button></form>";
}

sub return_to_backup_config {
    my ( $self, $host, $port, $security_token, $delay ) = @_;
    my $path              = q{scripts/backup_configuration/backupConfiguration};
    my $backup_config_url = sprintf( "https://%s:%s%s/%s", $host, $port, $security_token, $path );

    # When the delay is less than zero, display a button to go back once they are ready
    if ( $delay < 0 ) {
        my $locale = Cpanel::Locale->get_handle();
        print $self->_get_button( $backup_config_url, $locale->maketext("Continue") );
        return;
    }
    return $self->_refresh( $backup_config_url, $delay );
}

sub build_jb_url {
    my ( $self, $host, $port, $security_token ) = @_;
    return sprintf( "https://%s:%s%s/%s", $host, $port, $security_token, $JETBACKUP_CGI_RELATIVE );
}

sub return_to_jetbackup_plugin {
    my ( $self, $host, $port, $security_token, $delay ) = @_;
    my $jb_url = build_jb_url( $self, $host, $port, $security_token );
    return $self->_refresh( $jb_url, $delay );
}

sub _refresh {
    my ( $self, $url, $delay ) = @_;
    $url   = Cpanel::Encoder::Tiny::safe_html_encode_str($url);
    $delay = ( defined $delay ) ? int $delay : $REFRESH_DELAY;
    return print qq{<meta http-equiv="refresh" content="$delay; url=$url" />};
}

# Display error then redirect user to the Backup Config page to start over or do something else
sub _handle_jetbackup_error {
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
    return $self->return_to_backup_config( $args_hr->{'host'}, $args_hr->{'port'}, $args_hr->{'security_token'}, $delay );
}

# Determines if we should be showing the JetBackup options anywhere in the UI.
# Currently called by whostmgr7
sub show_jetbackup {
    my ($self) = @_;

    # JetBackup already installed, so the links serve no use.
    if ( is_jetbackup_installed() ) {
        return ( 0, 'JetBackup is already installed' );
    }

    # If we already have a JetBackup license, the links will give an error as such after a couple steps.
    my ( $rc, undef ) = $self->get_jetbackup_license();
    if ( defined $rc && $rc == 1 ) {
        return ( 0, 'This server already has a JetBackup license' );
    }

    # If we don't see any JetBackup package available from the server's store, don't show the links
    my $found_jb_pkg = 0;
    my $pkg_list_ar  = get_all_available_store_packages();
    foreach my $package ( @{$pkg_list_ar} ) {
        if ( exists $package->{'display_name'} && $package->{'display_name'} =~ /jetbackup/i ) {
            $found_jb_pkg++;
        }
    }
    if ( $found_jb_pkg == 0 ) {
        return ( 0, 'JetBackup was not found in the store' );
    }

    # If this server is under a partner and they have disabled JetBackup in manage2, don't show it
    my $advertising_preference = eval { get_company_advertising_preferences() };
    if ( exists $advertising_preference->{'disabled'} and $advertising_preference->{'disabled'} == 1 ) {
        return ( 0, 'JetBackup promotion is disabled by licensing party' );
    }

    # Otherwise, if LS isn't already installed, and it doesn't already have a license, and it's showing in the store, and the license "company" hasn't disabled it, show the links
    return ( 1, '' );
}

sub get_all_available_store_packages {
    my $package_list = [];
    eval {
        my $store = Cpanel::cPStore->new();
        $package_list = $store->get('products/cpstore');
    };
    return $package_list;
}

sub get_current_store_price {
    my ($self) = @_;
    my $package_list_ar = $self->get_all_available_store_packages();
    foreach my $product ( @{$package_list_ar} ) {
        if ( $product->{'short_name'} eq 'JetBackup Monthly' ) {
            return $product->{'price'};
        }
    }
    return 'Price Unavailable';
}

# Copied from KernelCare > LiteSpeed > here
sub get_company_advertising_preferences {
    require Cpanel::License::CompanyID;
    require Cpanel::JSON;
    require Cpanel::Exception;

    my $id = Cpanel::License::CompanyID::get_company_id();
    chomp $id if defined $id;

    die Cpanel::Exception->create("Cannot determine company ID.") if !$id;
    die Cpanel::Exception->create("Invalid company ID.")          if $id !~ m/^\d+$/;

    my $URL = sprintf( '%s/jetbackup.cgi?companyid=%s', Cpanel::Config::Sources::get_source('MANAGE2_URL'), $id );

    my $client   = Cpanel::HTTP::Client->new( timeout => 20 )->die_on_http_error();
    my $response = $client->get($URL);

    die Cpanel::Exception::create('HTTP') if !$response->{success};

    return Cpanel::JSON::Load( $response->{content} );
}

# Shortcut to the commands in jetbackupapi
sub jb_cmd {
    my ( $self, @cmd_args ) = @_;

    my $cmd = Cpanel::SafeRun::Object->new(
        'program'      => $JETAPPS_BIN,
        'args'         => [@cmd_args],
        'keep_env'     => 0,
        'timeout'      => (600),          # 10 minutes
        'read_timeout' => (600),
    );
    if ( !$cmd ) {
        return ( 0, '', "The command failed to run: $!" );
    }
    elsif ( $cmd->error_code() ) {
        return ( 0, $cmd->stdout, $cmd->stderr );
    }
    else {
        return ( 1, $cmd->stdout, $cmd->stderr );
    }
}

sub ensure_using_latest_license {
    my ( $self, $serial_no ) = @_;
    if ( !$serial_no ) {
        return ( 0, 'This call requires the license key serial number as an argument', '' );
    }
    my $cmd = Cpanel::SafeRun::Object->new(
        'program'      => $JETBACKUP_API_BIN,
        'args'         => [ '-F', 'licenseStatus', '-O', 'json' ],
        'keep_env'     => 0,
        'timeout'      => (60),                                      # 1 minute
        'read_timeout' => (60),
    );

    my $need_to_resync_license = 0;

    require JSON::XS;
    my $output_json = eval { JSON::XS::decode_json( $cmd->stdout ); };

    # Successful message is 'Your license is valid and active'

    if ( $output_json->{'message'} eq 'Your license is valid and active' ) {
        return ( 2, 'Valid license currently installed', '' );
    }
    else {
        my $resync_cmd = Cpanel::SafeRun::Object->new(
            'program'      => $JETBACKUP_BIN,
            'args'         => ['--license'],
            'keep_env'     => 0,
            'timeout'      => (60),             # 1 minute
            'read_timeout' => (60),
        );
        if ( $resync_cmd->stdout =~ m/^License was cleared/ ) {
            return ( 1, 'License successfully resynced', '' );
        }
        else {
            return ( 0, $resync_cmd->stdout, $resync_cmd->stderr );
        }
    }
}

1;

__END__

=head1 NAME

Whostmgr::JetBackup - encapsulates much of the behavior related to the purchase and installation of JetBackup through WHM

=head1 SYNOPSIS

  my $handler = Whostmgr::JetBackup->new();

  #... see whostmgr/bin/whostmgr12.pl for main use of this module

=head1 DESCRIPTION

This module was created to manage the implementation of the JetBackup purchase and installation
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

=item get_jetbackup_product_id

Makes a call to the cPanel Store to determine the actual product_id used by the monthly JetBackup purchase option

=item ensure_jetbackup_installed

Manages checking for and installing the JetBackup plugin upon successful purchase; the actual installation procedure
is encapsulated in C<install_jetbackup> function

=item is_jetbackup_installed

Simple check to ensure that lsws.cgi is a file and the admin directory exists (see $JETBACKUP_DIR4 or $JETBACKUP_DIR5 and $JETBACKUP_CGI)

=item return_to_jetbackup_plugin

Redirects back to WHM with the JetBackup plugin loaded as the main frame target

=item return_to_backup_config

Redirects back to WHM with Backup Config loaded as the main frame target

=item build_jb_url

Takes in core components of the URL and returns the full thing based on server settings

=item ensure_using_latest_license

Takes a serial from the license server and ensures that the current JetBackup install has a valid license, otherwise it will
try to resync the license

=item get_all_available_store_packages

Gets a full list of all the packages available from the cPStore and returns them

=item get_company_advertising_preferences

Checks an endpoint on manage2 to get and return preferences set by a partner account in manage2. The primary use for this currently is
to see whether or not the partner wants the promo banner to not show on their customers' Backup Configuration page

=item get_current_store_price

Finds the monthly price (USD) for JetBackup from the cPStore and returns it

=item get_jetbackup_license

Gets the current license information from the license server

=item install_jetbackup

Creates a Cpanel::PackMan instance to handle installation of several key JetApps/JetBackup related packages, and finally uses the
jetapps CLI API tool to install jetbackup itself

=item jb_cmd

Passes arguments to the jetapps tool via a SafeRun object

=item show_jetbackup

Determines from a variety of factors whether or not the UI should show the JetBackup plugin promotional banner

=back

=head2 INTERNAL METHODS

=over 4

=item _verify_jetbackup_license

Queries cPanel for licenses associated with the main server ip and checks to see if JetBackup is currently listed as an active and valid license

=item _refresh

Requires 1 parameter (refresh URL). Accepts a second optional parameter to set the refresh delay. Default is the value of the package variable C<$Whostmgr::JetBackup::REFRESH_DELAY>.

Delayed refresh via meta refresh tag, separated out for testing purposes.

=item _handle_jetbackup_error

General error handler, used when $@ is detected or some other error needs to halt the JetBackup purchase process. Logs all errors.

=item _end_html_output

Closes the HTML output on the installer page

=item _find_bash_bin

Determines location of the bash executable. Currently only has one option since Centos is all we support, but easily expandable in the future.

=item _revert_install_changes

Takes "history" arguments and attempts to revert installations made during an install that fails, to help ensure we aren't leaving cruft behind

=item _get_button

Takes the URL and button text as arguments and returns the html for it


=back

=head1 LICENSE AND COPYRIGHT

Copyright 2022, cPanel, L.L.C. All rights reserved.
