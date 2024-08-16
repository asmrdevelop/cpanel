package Cpanel::SSLInstall;

# cpanel - Cpanel/SSLInstall.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use IO::Handle ();
use Try::Tiny;

use Cpanel::Encoder::Tiny                ();
use Cpanel::Config::userdata             ();
use Cpanel::Config::userdata::Guard      ();
use Cpanel::Config::userdata::Utils      ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::PwCache                      ();
use Cpanel::AcctUtils::Owner             ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Config::Httpd::IpPort               ();
use Cpanel::Config::LoadCpConf                  ();
use Cpanel::Config::userdata                    ();
use Cpanel::Config::userdata::CacheQueue::Adder ();
use Cpanel::Config::userdata::Guard             ();
use Cpanel::Config::userdata::Load              ();
use Cpanel::Config::WebVhosts                   ();
use Cpanel::Debug                               ();
use Cpanel::Domain::Owner                       ();
use Cpanel::Validate::Domain                    ();
use Cpanel::Domain::TLS::Write                  ();
use Cpanel::Exception                           ();
use Cpanel::FileUtils::Access                   ();
use Cpanel::FileUtils::Open                     ();
use Cpanel::Hostname                            ();
use Cpanel::HttpUtils::ApRestart::BgSafe        ();
use Cpanel::HttpUtils::Conf                     ();
use Cpanel::IPv6::UserDataUtil::Key             ();
use Cpanel::Debug                               ();
use Cpanel::NAT                                 ();
use Cpanel::PwCache                             ();
use Cpanel::Reseller                            ();
use Cpanel::ServerTasks                         ();
use Cpanel::SSL::Utils                          ();
use Cpanel::SSL::Objects::Certificate           ();
use Cpanel::SSLInstall::Propagate               ();
use Cpanel::WildcardDomain                      ();
use Cpanel::WildcardDomain::Tiny                ();
use Whostmgr::ACLS                              ();
use Whostmgr::AcctInfo::Owner                   ();

our $VERSION = '2.2';

our $MAXIMUM_TIME_AUTOSSL_RUN_BEFORE_APRESTART = 3600;

use constant USER_FOR_UNOWNED_DOMAINS => 'nobody';

my $locale;

{
    my $init;

    sub _init {
        return if $init;

        # avoid to compile in shipped Cpanel::SSL* modules in cpanel.pl
        #   lazy load the modules at run time

        # use multiple lines for PPI parsing purpose
        require Cpanel::SSL::Utils;            # PPI USE OK
        require Cpanel::SSLInfo;               # PPI USE OK
        require Cpanel::Apache::TLS::Write;    # PPI USE OK

        return 1;
    }
}

#named arguments: domain, ip, crt, key, cab, disclose_user_data
#
#Returns a single hashref with "status", "message", "action", etc.,
#loosely in imitation of real_installssl().
sub install_or_do_non_sni_update {
    my %OPTS = @_;

    my $installssl_hr = real_installssl(%OPTS);

    $installssl_hr->{'statusmsg'} = $installssl_hr->{'apache_errors'} || $installssl_hr->{'message'};

    return $installssl_hr;
}

sub _determine_ip_to_install_for_unowned {
    my %args = @_;

    require Cpanel::Locale;
    $locale ||= Cpanel::Locale->get_handle();

    $args{'ip'} //= do {
        my $vh_conf = Cpanel::Config::userdata::Load::load_ssl_domain_userdata( USER_FOR_UNOWNED_DOMAINS(), $args{'domain'} );
        if ( $vh_conf && %$vh_conf ) {
            $args{'ip'} = $vh_conf->{'ip'} or do {
                die "Existing SSL vhost config for “$args{'domain'}” lacks “ip”!\n";
            };
        }
    };

    # This function is only called for 'nobody' (installs where there is no user attached) installs which is
    # almost none at this point so we should only load these expensive modules on demand
    require Cpanel::IP::Loopback;
    require Cpanel::IP::LocalCheck;
    require Cpanel::DIp::Owner;

    # No IP, no good
    if ( !$args{'ip'} ) {
        if ( Whostmgr::ACLS::hasroot() ) {

            # Output in html as well as 'message' is <pre>d'
            return ( 0, $locale->maketext( 'The domain “[_1]” is not managed on this server. You must specify an IP address to install SSL for “[_1]” or set up this domain on a new account, or create it as parked domain, a subdomain, or an addon domain of an existing account, and try again.', $args{'domain'} ) );
        }
        else {
            return (
                0,
                $locale->maketext(
                    'The domain “[_1]” is not managed on this server. You do not have sufficient privileges to install SSL for it. Only root may install SSL websites for domains that are not already set up on the server. Please set up this domain on a new account, or create it as parked domain, a subdomain, or an addon domain of an existing account that you own, and try again.',
                    $args{'domain'}
                )
            );
        }
    }
    elsif ( $args{'ip'} !~ m/^\d+\.\d+\.\d+\.\d+$/ ) {

        # Output in html as well as 'message' is <pre>d'
        return ( 0, $locale->maketext( '“[_1]” is not a valid IP address.', Cpanel::NAT::get_public_ip( $args{'ip'} ) ) );
    }

    # Make sure IP is up on the interface, otherwise Apache will fail to start
    elsif ( Cpanel::IP::Loopback::is_loopback( $args{'ip'} ) ) {
        return ( 0, $locale->maketext( 'You cannot use “[_1]” because this address is bound to a loopback interface.', $args{'ip'} ) );
    }
    elsif ( !Cpanel::IP::LocalCheck::ip_is_on_local_server( $args{'ip'} ) ) {
        return ( 0, $locale->maketext( 'You must use an IP address that is on the server. “[_1]” is not bound.', Cpanel::NAT::get_public_ip( $args{'ip'} ) ) );
    }

    my $ip_owner = Cpanel::DIp::Owner::get_dedicated_ip_owner( $args{'ip'} );

    if ($ip_owner) {
        my $message;
        if ( $args{'disclose_user_data'} ) {
            $message = $locale->maketext( 'The IP address “[_1]” is dedicated to the user “[_2]”.', Cpanel::NAT::get_public_ip( $args{'ip'} ), $ip_owner ) . " \n";
            if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain( $args{'domain'} ) ) {
                $message .= $locale->maketext( 'If you really want to install this certificate on this IP address, then you must add the domain “[_1]” (or any domain that matches “[_1]”) to the “[_2]” account before you continue.', $args{'domain'}, $ip_owner );
            }
            else {
                $message .= $locale->maketext( 'If you really want to install this certificate on this IP address, you must add the domain “[_1]” to the “[_2]” account before you continue.', $args{'domain'}, $ip_owner );
            }
        }
        else {
            $message = $locale->maketext( 'The IP address “[_1]” is dedicated to another user.', Cpanel::NAT::get_public_ip( $args{'ip'} ) ) . " \n";
            if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain( $args{'domain'} ) ) {
                $message .= $locale->maketext( 'If you really want to install this certificate on this IP address, then you must add the domain “[_1]” (or any domain that matches “[_1]”) to the account before you continue.', $args{'domain'} );
            }
            else {
                $message .= $locale->maketext( 'If you really want to install this certificate on this IP address, then you must add the domain “[_1]” to the account before you continue.', $args{'domain'} );
            }
        }

        return ( 0, $message );
    }

    return ( 1, $args{'ip'} );
}

#Takes:
#   domain
#   crt
#   key
#   ip (optional)
#   cab (optional)
#   disclose_user_data (default: off)
#     If set error will include user identifiable that is only intended for the
#     system admin.  Example: if there is a conflict, the error will show
#     which user the ssl install is conflicting with.  Do not set this flag
#     when returning information to the user as it will disclose data about
#     other users on the system.
#   user_sslstorage (optional)
#     If user_sslstorage is already open, this is an Cpanel::SSLStorage::User
#     object
#   apache_tls (optional)
#     If apache_tls is already open, this is a Cpanel::Apache::TLS::Write
#     object
#   skip_vhost_update (optional, default: off)
#     If set the webserver vhost will not be updated and the webserver will
#     not be restarted.  This is intended to be used during an account restore
#     where we do all the vhost updates at the end of the restore.
#Returns a single hashref with various properties, especially:
#   status
#   message
sub real_installssl {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my %args = @_;

    _init();

    require Cpanel::Locale;
    $locale ||= Cpanel::Locale->get_handle();

    ## !! NO OUTPUT TO STD* !! ##

    my $output = {
        'status'  => 0,
        'message' => '',
        'html'    => '',
        'action'  => 'install',    #auto detected if we want to update the cert
    };

    if ( !length $args{'domain'} ) {
        $output->{'message'} = $locale->maketext('You must specify a domain.');
        return $output;
    }
    else {
        $args{'domain'} =~ s{\A\s+|\s+\z}{}g;
        $args{'domain'} = lc $args{'domain'};
        $args{'domain'} =~ s{\Awww\.}{};

        if ( !Cpanel::Validate::Domain::valid_wild_domainname( $args{'domain'} ) ) {
            $output->{'message'} = $locale->maketext( '“[_1]” is not a valid domain.', $args{'domain'} );
            return $output;
        }
    }

    # Check for Certificate data
    # NOTE: "Sorry, ..." will be caught below in the cert and key parses.
    if ( !length $args{'crt'} || !length $args{'key'} ) {
        $output->{'message'} = $locale->maketext('A certificate and private key must be provided.');
        return $output;
    }
    else {
        $args{'crt'} = Cpanel::SSLInfo::demunge_ssldata( $args{'crt'} );    # PPI NO PARSE
        $args{'key'} = Cpanel::SSLInfo::demunge_ssldata( $args{'key'} );    # PPI NO PARSE
    }

    # The CA Bundle is optional
    # Lookup among default CA bundles
    _ensure_cabundle_if_needed( \$args{'cab'}, $args{'crt'} );

    my ( $components_ok, $components ) = _validate_ssl_components( @args{qw( crt key cab )} );
    if ( !$components_ok ) {
        $output->{'message'} = $components;
        $output->{'html'}    = Cpanel::Encoder::Tiny::safe_html_decode_str( $output->{'message'} );
        return $output;
    }

    my $cert_parse = $components->{'crt'};
    my $cert_obj   = Cpanel::SSL::Objects::Certificate->new_from_parsed_and_text( $cert_parse, $args{'crt'} );

    #
    # SECURITY: when this is called from ssladmin we force ENV{'REMOTE_USER'} to be the user who
    # has called the admin binary which allows this check to work as excepted
    #
    my $installing_user = $args{'installing_user'} || $ENV{'REMOTE_USER'};

    my $domainowner         = Cpanel::Domain::Owner::get_owner_or_undef( $args{'domain'} );
    my $domain_has_an_owner = !!$domainowner;

    my $servername_to_install_on;

    if ($domain_has_an_owner) {
        if ( Cpanel::Config::userdata::Load::user_has_domain( $domainowner, $args{'domain'} ) ) {
            $servername_to_install_on = $args{'domain'};
        }
        else {
            my $wvh = Cpanel::Config::WebVhosts->load($domainowner);
            $servername_to_install_on = $wvh->get_vhost_name_for_domain( $args{'domain'} );
            $servername_to_install_on ||= $wvh->get_vhost_name_for_ssl_proxy_subdomain( $args{'domain'} );
        }

        if ( !$servername_to_install_on ) {
            $output->{'message'} = "Can’t find web vhost for $domainowner’s domain “$args{'domain'}”!";
            $output->{'html'}    = Cpanel::Encoder::Tiny::safe_html_decode_str( $output->{'message'} );
            return $output;
        }
    }
    else {
        $domainowner              = USER_FOR_UNOWNED_DOMAINS();
        $servername_to_install_on = $args{'domain'};
    }

    $output->{'user'} = $domainowner;    # set early in case of error

    # Verify that whoever is doing this has access to that domain.
    # This will reject non-root resellers trying to install SSL for an
    # unmanaged domain.
    #
    # SECURITY: when this is called from ssladmin we force ENV{'REMOTE_USER'} to be the user who
    # has called the admin binary which allows this check to work as excepted
    #
    if ( ( $args{'installing_user'} || !Whostmgr::ACLS::hasroot() ) && ( $installing_user ne $domainowner ) ) {
        if ( Cpanel::Reseller::isreseller($installing_user) ) {
            if ( !Whostmgr::AcctInfo::Owner::checkowner( $installing_user, $domainowner ) ) {

                # If the text of this message changes, update bin::autossl_check_cpstore_queue::_process_user
                $output->{'html'} = $output->{'message'} = $locale->maketext( 'You cannot install SSL for the domain “[_1]” because neither you nor any of your owned accounts controls a domain with that name.', $args{'domain'} );

                # Output in html as well as 'message' is <pre>d'
                return $output;
            }
        }
        else {
            # If the text of this message changes, update bin::autossl_check_cpstore_queue::_process_user
            $output->{'html'} = $output->{'message'} = $locale->maketext( 'You cannot install SSL for the domain “[_1]” because you do not control a domain with that name.', $args{'domain'} );

            # Output in html as well as 'message' is <pre>d'
            return $output;
        }
    }

    my $host_text;
    if ( $servername_to_install_on ne $args{'domain'} ) {
        $host_text = $locale->maketext( '[_1]–alias of ‘[_2]’[comment,this is used as a variable so it needs to be semi-odd (en dash, single curly,long comment) to help indicate it is not meant for normal use]', $args{'domain'}, $servername_to_install_on );
    }
    else {
        $host_text = $args{'domain'};
    }

    # Only allow the install if at least one of the domains on the certificate matches
    # one of the domains on the vhost.  We have already established that they own the
    # domain on the vhost so its ok to allow any domain on the vhost since ownership
    # of any domain on the vhost is enough to prove they own the vhost
    #
    # case CPANEL-4093: We previously only validated againt the domain that was passed in
    # Since we know all the names on the vhost we can check them all to avoid rejecting
    # a restore of an addon domain
    my @all_installable_domains;

    my $parse_non_ssl_yn = ();

    if ( $domainowner eq USER_FOR_UNOWNED_DOMAINS() ) {
        @all_installable_domains = (
            $servername_to_install_on,
            "www.$servername_to_install_on",
        );

        my ( $ip_ok, $ip_to_install ) = _determine_ip_to_install_for_unowned(%args);
        if ( !$ip_ok ) {
            $output->{'html'} = $output->{'message'} = $ip_to_install;
            return $output;
        }

        $args{'ip'} = $ip_to_install;
    }
    elsif ( !Cpanel::Config::userdata::Load::user_has_domain( $domainowner, $servername_to_install_on ) ) {
        $output->{'html'} = $output->{'message'} = "“$domainowner” has no non-SSL vhost for “$servername_to_install_on”.";

        return $output;
    }
    else {
        my $non_ssl_vh_ud = Cpanel::Config::userdata::Load::load_userdata_domain_or_die( $domainowner, $servername_to_install_on );

        my $vhost_ip = $non_ssl_vh_ud->{'ip'} or do {
            $output->{'html'} = $output->{'message'} = "“$servername_to_install_on” has no configured IP address.";

            return $output;
        };

        if ( $args{'ip'} && ( $args{'ip'} ne $vhost_ip ) ) {
            $output->{'html'} = $output->{'message'} = "Given “ip” ($args{'ip'}) doesn’t match non-SSL vhost IP ($vhost_ip).";

            # Output in html as well as 'message' is <pre>d'
            return $output;
        }

        $args{'ip'} = $vhost_ip;

        @all_installable_domains = Cpanel::Config::userdata::Utils::get_all_vhost_domains_from_vhost_userdata($non_ssl_vh_ud);
    }

    my $domain_match = Cpanel::SSL::Utils::validate_domains_lists_have_match( $cert_parse->{'domains'}, \@all_installable_domains );    # PPI NO PARSE

    my $domain_is_owned = ( $domainowner ne USER_FOR_UNOWNED_DOMAINS() );

    if ( !$domain_match && $domain_is_owned ) {

        # If there isn't a match try adding ssl service (formerly proxy) subdomains.
        # since loading all the proxy ssl domains is expensive we
        # only load them if it doesn't match without them
        push @all_installable_domains, Cpanel::Config::WebVhosts->load($domainowner)->ssl_proxy_subdomains_for_vhost($servername_to_install_on);
        $domain_match = Cpanel::SSL::Utils::validate_domains_lists_have_match( $cert_parse->{'domains'}, \@all_installable_domains );    # PPI NO PARSE
    }
    if ( !$domain_match ) {
        $output->{'html'} = $output->{'message'} = $locale->maketext( 'The certificate does not support the domain “[_1]”. It supports [numerate,_2,this domain,these domains]: [list_and,_3].', $args{'domain'}, scalar @{ $cert_parse->{'domains'} }, $cert_parse->{'domains'} );
        return $output;
    }

    my ( $ok, $message ) = Cpanel::SSL::Utils::validate_allowed_domains( $cert_parse->{'domains'} );
    if ( !$ok ) {
        $output->{'html'} = $output->{'message'} = $message;
        return $output;
    }

    if ( !$domain_has_an_owner ) {

        # Remove domain from reseller's stats upon successful add
        # Only do this with USER_FOR_UNOWNED_DOMAINS since USER_FOR_UNOWNED_DOMAINS (root) is the only one
        # who can add domains via an ssl install
        require Cpanel::Domains;
        Cpanel::Domains::del_deleted_domains( USER_FOR_UNOWNED_DOMAINS, USER_FOR_UNOWNED_DOMAINS, '', [ $args{'domain'} ] );
    }

    # During a restore we do not update sslstorage since the cert will
    # already be in there.
    if ($domain_has_an_owner) {

        try {
            # Update certificate files in user's home directory (don't do for USER_FOR_UNOWNED_DOMAINS user)
            my ( $user_ok, $user_ssldatastore );
            if ( $args{'user_sslstorage'} ) {
                $user_ok           = 1;
                $user_ssldatastore = $args{'user_sslstorage'};
            }
            else {
                require Cpanel::SSLStorage::User;
                ( $user_ok, $user_ssldatastore ) = Cpanel::SSLStorage::User->new( user => $domainowner );

                if ( !$user_ok ) {
                    die $user_ssldatastore;
                }
            }
            $user_ssldatastore->add_key_and_certificate_if_needed( key => $args{'key'}, cert => $args{'crt'}, key_friendly_name => "Key for “$servername_to_install_on”", cert_friendly_name => "Cert for “$servername_to_install_on”" );
        }
        catch {
            Cpanel::Debug::log_warn("The system could not add the certificate and key to sslstorage for the user “$domainowner” because of an error: $_");
        };
    }

    my $ip = $args{'ip'};

    my $domain_has_ssl = Cpanel::Config::userdata::Load::user_has_ssl_domain( $domainowner, $servername_to_install_on );

    my $ssl_port = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

    my $cert_is_already_installed_on_this_host;

    my $userdata_serveralias;

    my $ssl_userdata;

    if ($domain_has_ssl) {

        #We can just return if we already have the same certificate and
        #CA bundle already installed on this domain.
        $ssl_userdata = Cpanel::Config::userdata::Load::load_ssl_domain_userdata( $domainowner, $servername_to_install_on, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
        if ( !$ssl_userdata ) {
            $output->{'html'} = $output->{'message'} = $locale->maketext( 'The SSL install cannot proceed because the system failed to load the SSL userdata file for “[_1]”.', $servername_to_install_on );
            return $output;
        }

        if ( $ssl_userdata->{'ip'} ne $ip ) {
            $output->{'html'} = $output->{'message'} = $locale->maketext( '“[_1]” already has SSL installed on the IP address “[_2]”. The same domain cannot have SSL on more than one IP address.', $host_text, Cpanel::NAT::get_public_ip( $ssl_userdata->{'ip'} ) );
            return $output;
        }
    }

    my ($gid) = ( Cpanel::PwCache::getpwnam_noshadow($domainowner) )[3];

    my $apache_tls = $args{'apache_tls'} || Cpanel::Apache::TLS::Write->new();    # PPI NO PARSE -- loaded in init

    my ( $crt, @cab );

    if ($domain_has_ssl) {
        my %new = ();

        # CPANEL-17667: Use the combined file as the source of truth
        # to determine which cab is in use as third party software
        # or humans may have caused the combined and certificates file
        # to be out of sync.
        ( my $oldkey, $crt, @cab ) = $apache_tls->get_tls($servername_to_install_on);    ## no critic qw(Variables::ProhibitUnusedVariables)

        if ( defined $crt && $crt eq $args{'crt'} ) {
            $cert_is_already_installed_on_this_host = 1;
        }

        $userdata_serveralias = $ssl_userdata->{'serveralias'};
    }

    my @key_and_chain_to_propagate;

    if ($cert_is_already_installed_on_this_host) {
        my $already_msg = $locale->maketext('This certificate was already installed on this host.');

        my ( $msg, $updated_cab_yn );

        #Check to see if we need to update the CA bundle.
        if ( $args{'cab'} ) {
            if ( !@cab || _should_update_cab( $args{'cab'}, @cab ) ) {
                $updated_cab_yn = 1;

                my $ok;
                try {
                    $apache_tls->set_tls__no_verify(
                        vhost_name  => $servername_to_install_on,
                        key         => $args{'key'},
                        certificate => $cert_obj,
                        cabundle    => $args{'cab'},
                    );
                    $ok = 1;
                }
                catch {
                    $msg                 = Cpanel::Exception::get_string($_);
                    $output->{'message'} = $msg;
                    $output->{'html'}    = Cpanel::Encoder::Tiny::safe_html_encode_str($msg);
                };

                if ( !$ok ) {
                    return $output;
                }
            }
        }

        # We propagate to the remote even if no local change happened
        # because this will correct a remote that’s gotten out of sync
        # with the controller.
        @key_and_chain_to_propagate = (
            $args{'key'},
            $cert_obj->text(),
            $args{'cab'} || (),
        );

        $output->{'status'} = 1;

        if ($updated_cab_yn) {
            $output->{'action'} = 'update_cabundle';
            $msg = "$already_msg " . $locale->maketext('The system updated the Certificate Authority bundle for the current SSL installation.');
        }
        else {
            $output->{'action'} = 'none';
            $msg = "$already_msg " . $locale->maketext('The system made no changes.');
        }

        $output->{'message'} .= $msg;
        $output->{'html'}    .= "<br /><b>$msg</b><br />\n";
    }
    else {
        #Ok, we actually have to make a vhost, which requires some digging
        #to get things like a docroot and homedir.

        my $old_userdata = $ssl_userdata;
        my $new_userdata;

        #Now that we use Cpanel::Apache::TLS to determine the path for SSL
        #resources, the userdata no longer needs to contain this information.
        if ($old_userdata) {
            $new_userdata = $ssl_userdata;
        }
        else {
            ( my $new_userdata_ok, $new_userdata ) = _create_ssl_userdata(
                servername => $servername_to_install_on,
                ip         => $ip,
            );

            if ( !$new_userdata_ok ) {
                $output->{'message'} = $new_userdata;
                $output->{'html'}    = '<b>' . $new_userdata . '</b>';

                return $output;
            }
        }

        $userdata_serveralias = $new_userdata->{'serveralias'};

        my @rollbacks;

        my $do_rollback = sub {
            $_->() for reverse splice @rollbacks;
        };

        my $atls_err;
        try {
            $apache_tls->set_tls__no_verify(
                vhost_name  => $servername_to_install_on,
                key         => $args{'key'},
                certificate => $cert_obj,
                cabundle    => $args{'cab'},
            );

            @key_and_chain_to_propagate = (
                $args{'key'},
                $cert_obj->text(),
                $args{'cab'} || (),
            );
        }
        catch {
            $output->{'message'} = Cpanel::Exception::get_string($_);
            $output->{'html'}    = Cpanel::Encoder::Tiny::safe_html_encode_str( $output->{'message'} );
            $do_rollback->();
            $atls_err = $_;
        };

        return $output if $atls_err;

        #TODO: Teach userdata::Guard to write without giving up the lock
        #so that we can more easily roll back in the event of failure.
        #
        #Also skip the ADDON_DOMAIN_CHECK_SKIP since we already resolve the servername
        Cpanel::Config::userdata::save_userdata_domain_ssl( $domainowner, $servername_to_install_on, $new_userdata, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP ) or do {
            $output->{'message'} = $locale->maketext( 'The system failed to save the SSL userdata file for “[_1]” because of an error: [_2]', $servername_to_install_on, $! );
            $output->{'html'}    = $output->{'message'};
            $do_rollback->();

            return $output;
        };

        my $update_userdata_cache = sub {
            Cpanel::Config::userdata::CacheQueue::Adder->add($domainowner);
            Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 10, 'update_userdata_cache' );
        };

        push @rollbacks, sub {
            if ($old_userdata) {

                #Also skip the ADDON_DOMAIN_CHECK_SKIP since we already resolve the servername
                Cpanel::Config::userdata::save_userdata_domain_ssl( $domainowner, $servername_to_install_on, $old_userdata, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
            }
            else {
                Cpanel::Config::userdata::remove_user_domain_ssl( $domainowner, $servername_to_install_on );
            }

            #We only need to roll this back here.
            #Even if this is a "USER_FOR_UNOWNED_DOMAINS" SSL install, which installs a subdomain
            #entry in "USER_FOR_UNOWNED_DOMAINS"'s main userdata, that will roll back before this,
            #so this cache update will catch both rollbacks.

            $update_userdata_cache->();
        };

        # TODO : The above is used to create the file, but does not lock. Need to reconsider.
        if ( !$domain_has_an_owner ) {
            require Cpanel::Config::LoadWwwAcctConf;

            # verify the domain is listed in USER_FOR_UNOWNED_DOMAINS's main datastore
            my $wwwacct       = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
            my $main_hostname = exists $wwwacct->{'HOST'} && $wwwacct->{'HOST'} ? $wwwacct->{'HOST'} : Cpanel::Hostname::gethostname();
            if ( $servername_to_install_on ne $main_hostname ) {
                my $guard       = Cpanel::Config::userdata::Guard->new($domainowner);
                my $ud_main_ref = $guard->data();
                unless ( grep { $servername_to_install_on eq $_ } @{ $ud_main_ref->{'sub_domains'} } ) {
                    push @{ $ud_main_ref->{'sub_domains'} }, $servername_to_install_on;
                    $guard->save();

                    push @rollbacks, sub {
                        my $guard         = Cpanel::Config::userdata::Guard->new($domainowner);
                        my $subdomains_ar = $guard->data()->{'sub_domains'};
                        @$subdomains_ar = grep { $_ ne $servername_to_install_on } @$subdomains_ar;
                        $guard->save();
                    };
                }
            }
        }

        # Create the domlogs for ssl_log's before Apache so that their permissions are correct
        my $domlog = apache_paths_facade->dir_domlogs() . '/' . Cpanel::WildcardDomain::encode_wildcard_domain($servername_to_install_on) . "-ssl_log";
        my $domlog_fh;
        if ( Cpanel::FileUtils::Open::sysopen_with_real_perms( $domlog_fh, $domlog, 'O_WRONLY|O_APPEND|O_CREAT', 0640 ) ) {
            Cpanel::FileUtils::Access::ensure_mode_and_owner( $domlog_fh, 0640, 0, $gid );
        }
        else {
            warn "Could not touch the log file “$domlog” for creation: $!";
        }

        # If skip_vhost_update is set:
        # This usually means we are doing an account restore and the vhost
        # will be created at the end in PostRestoreActions.

        unless ( $args{'skip_vhost_update'} ) {
            $update_userdata_cache->();

            require Cpanel::ConfigFiles::Apache::vhost;
            my ( $update_ok, $update_msg ) = Cpanel::ConfigFiles::Apache::vhost::update_domains_vhosts($servername_to_install_on);
            if ( !$update_ok ) {
                #
                # We used to rollback here in the event the update
                # of the vhosts failed, however that kept the ssl
                # storage locked for too long which would lead
                # to random failures.
                #
                # Since we know userdata
                # and sslstorage was already written any update
                # to httpd.conf that fails is likely due to
                # a disk problem or template problem which
                # is unlikely to get better with a rollback
                # so the rollback code was removed.
                #
                # If there is something really wrong with httpd.conf
                # chkservd is going to rebuild it after a few tries
                # to get apache up and running and hopefully
                # return the system to a good state.
                #
                $output->{'message'} .= $update_msg;
                $output->{'html'}    .= "<b>$update_msg</b>";
            }
        }

        $output->{'status'} = 1;    ## Great Success
        my $success_msg = $locale->maketext( 'The SSL certificate is now installed onto the domain “[_1]” using the IP address “[_2]”.', $host_text, Cpanel::NAT::get_public_ip( $args{'ip'} ) );
        $output->{'message'} .= $success_msg;

        $output->{'html'} .= qq{<br>$success_msg};

        if ($domain_has_ssl) {
            my $update_msg = $locale->maketext('The existing virtual host was updated with the new certificate.');
            $output->{'message'} .= "\n$update_msg";
            $output->{'html'}    .= "\n<br />\n$update_msg";
            $output->{'action'} = 'update';
        }

        # If skip_vhost_update is set:
        # This usually means we are doing an account restore and the vhost
        # will be created at the end in PostRestoreActions.

        unless ( $args{'skip_vhost_update'} ) {

            #NOTE: AutoSSL overrides this in the interest of only doing one
            #Apache restart per certificate install.
            _restart_apache();

            my $restart_msg = $locale->maketext('Apache is restarting in the background.');
            $output->{'message'} .= " $restart_msg\n";
            $output->{'html'}    .= "<br />$restart_msg";
        }
    }

    #For Domain TLS we want to be particular: no self-signed, expired, etc.
    #This is more stringent than Apache installs, which permit a few types of
    #invalid certs. (cf. Cpanel::SSLInfo)
    {
        my $c_domains_ar  = $cert_parse->{'domains'};
        my $vh_domains_ar = [
            $servername_to_install_on,
            split( m<\s+>, $userdata_serveralias ),
        ];

        #This might not actually be necessary, but we might as well
        #since it’s so cheap and avoids potential spurious warnings.
        Cpanel::Domain::TLS::Write->init();

        my @unset_domains;

        #We don’t just match on all the cert domains and all the vhost domains
        #because that can yield Domain TLS installations on domains that
        #aren’t actually on the vhost, which means that removing the SSL vhost
        #won’t actually remove the Domain TLS entry. For example:
        #
        # - cert covers foo.com and mail.foo.com
        # - vhost is *.foo.com
        #
        #If we did one big match, we’d end up with a Domain TLS entry for
        #“mail.foo.com”, and removing the SSL vhost for *.foo.com wouldn’t
        #remove the Domain TLS entry.
        for my $d (@$vh_domains_ar) {
            my $match_ar = Cpanel::SSL::Utils::find_domains_lists_matches(    # PPI NO PARSE
                [$d],
                $c_domains_ar,
            );

            #If the certificate matches any domains on the SSL vhost
            #and also passes full OpenSSL verification, then we put it
            #into Domain TLS for those matched domains.
            if ( @$match_ar && $components->{'verify'}->ok() ) {
                try {
                    Cpanel::Domain::TLS::Write->set_tls__no_verify(
                        domain      => $d,
                        key         => $args{'key'},
                        certificate => $cert_obj,
                        cabundle    => $args{'cab'},
                    );
                }
                catch {
                    $output->{'message'} .= "“$d” → Domain TLS: " . Cpanel::Exception::get_string($_);
                    Cpanel::Debug::log_warn( "“$d” → Domain TLS: " . Cpanel::Exception::get_string($_) );
                };
            }
            else {
                push @unset_domains, $d;
            }
        }
        if (@unset_domains) {
            try {

                #There might not actually be anything to unset,
                #but there’s little harm in just enqueuing it.
                Cpanel::Domain::TLS::Write->enqueue_unset_tls(@unset_domains);
            }
            catch {
                my $msg = "Domain TLS - enqueue removal of “@unset_domains”: " . Cpanel::Exception::get_string($_);
                $output->{'message'} .= $msg;
                Cpanel::Debug::log_warn($msg);
            };
        }

        _rebuild_doveconf_config_and_restart();
    }

    if ( @key_and_chain_to_propagate && $domain_is_owned && !$args{'skip_propagation'} ) {
        Cpanel::SSLInstall::Propagate::install(
            $domainowner,
            $servername_to_install_on,
            @key_and_chain_to_propagate,
        );
    }

    my $output_serveralias = $userdata_serveralias;
    $output_serveralias =~ s{(?:\A|\s+)www\.\S+}{}g;
    $output_serveralias =~ s{\A\s+|\s+\z}{}g;

    # Output raw data for ui
    $output->{'domain'}     = $args{'domain'};
    $output->{'servername'} = $servername_to_install_on;

    $output->{'aliases'} = $output_serveralias;
    $output->{'user'}    = $domainowner;
    $output->{'ip'}      = $args{'ip'};

    my $domain_lists_hr = Cpanel::SSL::Utils::split_vhost_certificate_domain_lists(    # PPI NO PARSE
        [ $servername_to_install_on, ( split m{\s+}, $output_serveralias ) ],
        $cert_parse->{'domains'},
    );

    return { %$output, %$domain_lists_hr };
}

#XXX: overridden in AutoSSL
sub _rebuild_doveconf_config_and_restart {
    Cpanel::ServerTasks::schedule_task( ['DovecotTasks'], 10, 'build_mail_sni_dovecot_conf', 'reloaddovecot' );

    return;
}

*_restart_apache = *Cpanel::HttpUtils::ApRestart::BgSafe::restart;

sub _should_update_cab {
    my ( $cab_text, @existing_cab ) = @_;

    my $old_text = join "\n", @existing_cab;

    require Cpanel::SSL::CABundleUtils;

    my $better_cab = Cpanel::SSL::CABundleUtils::pick_best_cabundle( $old_text, $cab_text );
    return $better_cab && ( $better_cab ne $old_text );
}

#required args:
#   servername
#   ip
sub _create_ssl_userdata {
    my (%OPTS) = @_;

    my ($servername_to_install_on) = $OPTS{'servername'};

    my $domainowner         = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $servername_to_install_on, { 'default' => USER_FOR_UNOWNED_DOMAINS } );
    my $domain_has_an_owner = $domainowner ne USER_FOR_UNOWNED_DOMAINS;

    #Get the homedir from the system.
    #This is needed for userdata.
    my $homedir;
    if ($domain_has_an_owner) {
        $homedir = Cpanel::PwCache::gethomedir($domainowner);
        if ( !$homedir ) {
            return ( 0, "Unable to get home directory for username $domainowner!" );
        }
    }
    if ( !$homedir || $homedir eq '/' ) {
        $homedir = apache_paths_facade->dir_docroot();
    }

    #Get the docroot from userdata if we can;
    #otherwise, use either Apache's default or ~/public_html.
    my ( $docroot, $apache_serveralias, $ipv6, $secruleengineoff, $hascgi );
    if ($domain_has_an_owner) {
        my $std_userdata = Cpanel::Config::userdata::Load::load_userdata_domain( $domainowner, $servername_to_install_on );
        $docroot            = $std_userdata->{'documentroot'};
        $hascgi             = $std_userdata->{'hascgi'} // 0;
        $apache_serveralias = $std_userdata->{'serveralias'};
        $ipv6               = $std_userdata->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key};
        $secruleengineoff   = $std_userdata->{'secruleengineoff'};
    }

    if ( !length $apache_serveralias ) {
        if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($servername_to_install_on) ) {
            $apache_serveralias = $servername_to_install_on;
        }
        else {
            $apache_serveralias = "www.$servername_to_install_on";
        }
    }
    $docroot ||= ( $homedir eq apache_paths_facade->dir_docroot() ) ? $homedir : "$homedir/public_html";

    my $serveradmin = $servername_to_install_on;
    $serveradmin =~ s/^\*\.//;
    $serveradmin = 'webmaster@' . $serveradmin;

    my ( $settings_dirprotect, $dirusers, $settings_phpopendir );

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    if ( $cpconf->{'userdirprotect'} ) {
        my $lookup_domain = $servername_to_install_on;

        # If we are installing SSL on the main domain, we have to look up 'DefaultHost' instead of the actual domain name
        if ( !$domain_has_an_owner ) {
            require Cpanel::Config::LoadWwwAcctConf;
            my $wwwacct       = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
            my $main_hostname = $wwwacct->{'HOST'} || Cpanel::Hostname::gethostname();
            if ( $main_hostname eq $lookup_domain ) {
                $lookup_domain = 'DefaultHost';
            }
        }
        ( $settings_dirprotect, $dirusers ) = Cpanel::HttpUtils::Conf::fetchdirprotectconf($lookup_domain);
    }
    if ( $cpconf->{'phpopenbasedirhome'} ) {
        $settings_phpopendir = Cpanel::HttpUtils::Conf::fetchphpopendirconf( $domainowner, $servername_to_install_on );
    }

    my $owner = Cpanel::AcctUtils::Owner::getowner($domainowner);

    my $ssl_port = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

    if ( !$domain_has_an_owner ) {
        $hascgi = 1;
    }

    my $userdata = {
        'documentroot'                             => $docroot,
        'group'                                    => $domainowner,
        'hascgi'                                   => $hascgi,
        'homedir'                                  => $homedir,
        'ip'                                       => $OPTS{'ip'},
        $Cpanel::IPv6::UserDataUtil::Key::ipv6_key => $ipv6,
        'owner'                                    => $owner,
        'phpopenbasedirprotect'                    => $settings_phpopendir,
        'port'                                     => $ssl_port,
        'secruleengineoff'                         => $secruleengineoff,
        'serveradmin'                              => $serveradmin,
        'serveralias'                              => $apache_serveralias,         # needed for legacy templates
        'servername'                               => $servername_to_install_on,
        'ssl'                                      => 1,

        #The SSL certificate, key, and CA bundle are, as of v68, stored in the
        #same file. This file’s path is a static function of the vhost name;
        #i.e., a certificate for $vhost_name will always be at the same path.
        #Thus, there is no need to store “sslcertificatefile” et al. in
        #userdata anymore. See Cpanel::Apache::TLS for more information.

        'usecanonicalname' => 'Off',
        'user'             => $domainowner,
        'userdirprotect'   => $settings_dirprotect ? $dirusers : '-1',
    };

    return ( 1, $userdata );
}

#This is validation to allow installation of the certificate
#into Apache TLS. We also hold onto the Verify::Result object
#so that we can determine whether the certificate is valid for
#Domain TLS. (We put self-signed and non-root-chained certs into
#Apache TLS but require full verification for Domain TLS.)
sub _validate_ssl_components {
    my ( $crt, $key, $cab ) = @_;

    _init();

    # second to last arg makes it quiet,
    # last arg disabled html errors (legacy)
    my ( $status, $result, $cert_parse, $key_parse, $verify_obj ) = Cpanel::SSLInfo::verifysslcert( undef, $crt, $key, $cab, 1, 1 );    # PPI NO PARSE

    return ( 0, $result ) if !$status;

    return ( 1, { 'crt' => $cert_parse, 'key' => $key_parse, 'verify' => $verify_obj } );
}

sub _ensure_cabundle_if_needed {
    my ( $cab_sr, $crt ) = @_;

    _init();

    if ( !$$cab_sr ) {
        my ( undef, undef, $cab ) = Cpanel::SSLInfo::fetchcabundle($crt);    # PPI NO PARSE
        $$cab_sr = $cab if Cpanel::SSLInfo::is_ssl_payload($cab);            # PPI NO PARSE
    }

    $$cab_sr &&= Cpanel::SSLInfo::demunge_ssldata($$cab_sr);                 # PPI NO PARSE

    return;
}

1;
