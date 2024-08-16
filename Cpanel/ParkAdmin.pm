package Cpanel::ParkAdmin;

# cpanel - Cpanel/ParkAdmin.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;
use Cpanel::AccessIds::ReducedPrivileges     ();
use Cpanel::Config::userdata                 ();
use Cpanel::Config::userdata::Utils          ();
use Cpanel::Exception                        ();
use Cpanel::PwCache                          ();
use Cpanel::AcctUtils::DomainOwner           ();
use Cpanel::AcctUtils::Account               ();
use Cpanel::AcctUtils::Domain                ();
use Cpanel::AcctUtils::DomainOwner::Tiny     ();
use Cpanel::AcctUtils::Owner                 ();
use Cpanel::ConfigFiles::Apache::vhost       ();
use Cpanel::App                              ();
use Cpanel::Config::ModCpUserFile            ();
use Cpanel::Config::LoadCpUserFile           ();
use Cpanel::Config::userdata::Load           ();
use Cpanel::Config::LoadCpConf               ();
use Cpanel::Config::WebVhosts                ();
use Cpanel::DKIM                             ();
use Cpanel::DKIM::Transaction                ();
use Cpanel::DIp::Update                      ();
use Cpanel::Domain::Owner                    ();
use Cpanel::Domain::TLS                      ();
use Cpanel::Domain::TLS::Write               ();
use Cpanel::DomainIp                         ();
use Cpanel::Domains                          ();
use Cpanel::EmailLimits                      ();
use Cpanel::Exim::ManualMX                   ();
use Cpanel::Encoder::Tiny                    ();
use Cpanel::FileUtils::Modify                ();
use Cpanel::Hooks                            ();
use Cpanel::HttpUtils::ApRestart::BgSafe     ();
use Cpanel::IPv6::User                       ();
use Cpanel::Locale                           ();
use Cpanel::Logger                           ();
use Cpanel::MailTools                        ();
use Cpanel::ParkAdmin::Pieces                ();
use Cpanel::PHPFPM                           ();
use Cpanel::PHPFPM::Get                      ();
use Cpanel::Proxy                            ();
use Cpanel::SPF                              ();
use Cpanel::SPF::Update                      ();
use Cpanel::ServerTasks                      ();
use Cpanel::SocketIP                         ();
use Cpanel::StringFunc::File                 ();
use Cpanel::SSL::Auto::Exclude::Set          ();
use Cpanel::SSL::Setup                       ();
use Cpanel::TextDB                           ();
use Cpanel::Userdomains                      ();
use Cpanel::Validate::Domain::Normalize      ();
use Cpanel::Validate::DomainCreation::Addon  ();
use Cpanel::Validate::DomainCreation::Parked ();
use Cpanel::Validate::IP::v4                 ();
use Cpanel::WebVhosts::ProxySubdomains       ();
use Cpanel::FtpUtils::Passwd                 ();
use Cpanel::Features::Check                  ();
use Cpanel::IPv6::Normalize                  ();
use Cpanel::LinkedNode::Worker::WHM          ();

$Cpanel::ParkAdmin::VERSION = '1.3';

my $logger = Cpanel::Logger->new();
my $locale;

sub unpark (%opts) {

    my $username = $opts{'user'} || die('need “user”');

    my ( $ok, $why );

    Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
        username => $username,

        local_action => sub {
            ( $ok, $why ) = _local_unpark(%opts);
        },

        remote_action => sub ($node_obj) {
            return if !$ok;    # skip if local failed

            warn if !eval {
                Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                    node_obj => $node_obj,
                    function => 'delete_domain',
                    api_opts => {
                        domain => $opts{'domain'},
                    },
                );
            };
        },
    );

    return ( $ok, $why );
}

# mocked in tests
sub _local_unpark {
    my %OPTS   = @_;
    my $domain = $OPTS{'domain'};

    my $parent_domain = $OPTS{'parent_domain'} || $Cpanel::CPDATA{'DNS'} || do {
        die '“parent_domain” wasn’t given, and CPDATA/DNS isn’t set.';
    };

    # Do not change to Cpanel::hasfeature as it will break WHM
    if ( !main::hasfeature('parkeddomains') && !main::hasfeature('addondomains') ) {
        $Cpanel::CPERROR{'park'} = "This feature is not enabled";
        return;
    }
    local $SIG{'HUP'} = 'IGNORE';

    $domain        = Cpanel::Validate::Domain::Normalize::normalize($domain);
    $parent_domain = Cpanel::Validate::Domain::Normalize::normalize($parent_domain);

    # Do not change to Cpanel::hasfeature as it will break WHM
    if ( $parent_domain eq ( $Cpanel::CPDATA{'DNS'} // q<> ) && !main::hasfeature('parkeddomains') ) {
        $Cpanel::CPERROR{'park'} = "This feature is not enabled";
        return;
    }

    my $trueuser = Cpanel::AcctUtils::DomainOwner::gettruedomainowner( $domain, { 'default' => '' } );

    if ($trueuser) {
        return ( 0, "You cannot unpark a user’s main domain name." );
    }

    my $user      = Cpanel::Domain::Owner::get_owner_or_undef($domain);
    my $validuser = 1;
    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        $validuser = 0;
        return ( 0, "Unable to find out which user owns the parked domain $domain.\n" );
    }

    my $wvh              = Cpanel::Config::WebVhosts->load($user);
    my $mainserverdomain = $wvh->get_vhost_name_for_domain($domain);

    if ( !defined $mainserverdomain || !length $mainserverdomain ) {
        $locale ||= Cpanel::Locale->get_handle();
        return ( 0, $locale->maketext( 'The system cannot determine the base domain for “[_1]” (i.e., the domain on which “[_1]” is parked).', $domain ) );
    }
    if ( $domain eq $mainserverdomain ) {
        $locale ||= Cpanel::Locale->get_handle();
        return ( 0, $locale->maketext( '“[_1]” is not a parked domain.', $domain ) );
    }

    # We need to identify any “subdomains” whose DNS depends on
    # the given $domain. If any exist, then we can’t proceed.
    my @subdomains_whose_zone_is_domain = Cpanel::ParkAdmin::Pieces::get_subdomains_whose_zone_is_domain( $user, $domain );

    # We also need to fail if any dynamic DNS subdomains
    # depend on $domain.
    require Cpanel::DynamicDNS::RootUtils;

    my @ddns_conflicts = Cpanel::DynamicDNS::RootUtils::get_ddns_domains_for_zone( $user, $domain );

    my $impeded_msg;

    if (@subdomains_whose_zone_is_domain) {
        $locale ||= Cpanel::Locale->get_handle();

        $impeded_msg = $locale->maketext( "Before the system can remove the “[_1]” parked domain, you must remove the [list_and_quoted,_2] [numerate,_3,subdomain,subdomains].", $domain, \@subdomains_whose_zone_is_domain, scalar @subdomains_whose_zone_is_domain );

        if (@ddns_conflicts) {
            $impeded_msg .= ' ' . $locale->maketext( 'You must also remove the [list_and_quoted,_1] dynamic DNS [numerate,_2,domain,domains].', \@ddns_conflicts, scalar @ddns_conflicts );
        }
    }
    elsif (@ddns_conflicts) {
        $locale ||= Cpanel::Locale->get_handle();

        $impeded_msg = $locale->maketext( "Before the system can remove the “[_1]” parked domain, you must remove the [list_and_quoted,_2] dynamic DNS [numerate,_3,domain,domains].", $domain, \@ddns_conflicts, scalar @ddns_conflicts );
    }

    return ( 0, $impeded_msg ) if $impeded_msg;

    #----------------------------------------------------------------------

    if ( !$parent_domain && Cpanel::Config::userdata::Load::is_parked_domain( $user, $domain ) ) {
        $parent_domain = Cpanel::AcctUtils::Domain::getdomain($user);
    }

    my $hook_info = {
        'category' => 'Whostmgr',
        'event'    => 'Domain::unpark',
        'stage'    => 'pre',
        'blocking' => 1,
    };

    my ( $pre_hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        $hook_info,
        {
            'domain'        => $domain,
            'parent_domain' => $parent_domain,
            'user'          => $user,
        },
    );
    return ( 0, Cpanel::Hooks::hook_halted_msg( $hook_info, $hook_msgs ) ) if !$pre_hook_result;

    # Run weblogs for user upon termination to gather final bandwidth for dead domain - Case 10734
    # Queue the call to runweblogs - Case 26118
    Cpanel::ServerTasks::queue_task( ['LogdTasks'], "runweblogs $user" );

    Cpanel::SSL::Auto::Exclude::Set::remove_user_excluded_domains_before_non_main_domain_removal( user => $user, remove_domain => $domain );

    if ( Cpanel::PHPFPM::Get::get_php_fpm( $user, $domain ) ) {
        Cpanel::PHPFPM::_removedomain($domain);
    }

    Cpanel::MailTools::removedomain($domain);
    if ($validuser) {
        my $owner = Cpanel::AcctUtils::Owner::getowner($user);
        Cpanel::Domains::add_deleted_domains( $user, $owner, '', [$domain] );
        Cpanel::Config::ModCpUserFile::adddomaintouser( 'user' => $user, 'domain' => $domain, 'type' => 'X' );    # this will remove the live domain if it exists
        Cpanel::Config::userdata::remove_parked_domain_data( { 'user' => $user, 'parked_domain' => $domain, 'domain' => $parent_domain } );
    }

    Cpanel::WebVhosts::ProxySubdomains::sync_base_vhost_if_needed( $user, $domain );

    # not checking return because a failure is not fatal. We remove the zone anyway.
    my $dkim = Cpanel::DKIM::Transaction->new();
    $dkim->tear_down_user_domains( $user, [$domain] );
    $dkim->commit();

    Cpanel::SPF::remove_a_domains_spf( 'domain' => $domain );

    #2ND OPTION IS NO-PRINT
    require Cpanel::DnsUtils::Remove;
    Cpanel::DnsUtils::Remove::removezone( $domain, 1 );

    if ( Cpanel::Domain::TLS->has_tls($domain) ) {
        Cpanel::ServerTasks::schedule_task( ['DovecotTasks'], 120, 'build_mail_sni_dovecot_conf', 'reloaddovecot' );
    }

    for my $d ( map { $_, "www.$_" } $domain ) {
        try {
            Cpanel::Domain::TLS::Write->enqueue_unset_tls($d);
        }
        catch {
            warn "Error while enqueueing removal of “$d” from Domain TLS: $_";
        };
    }

    if ($validuser) {

        # Case 92825 take special care with userdomains
        Cpanel::FileUtils::Modify::remlinefile( '/etc/userdomains', "$domain:", 'begin' );
        Cpanel::StringFunc::File::remlinefile( '/etc/email_send_limits', "$domain:", 'begin' );

        Cpanel::DIp::Update::update_dedicated_ips_and_dependencies_or_warn();
    }

    # Touch the ftp passwd file for the user
    # so that the 'list_ftp' cache is refreshed properly.
    Cpanel::FtpUtils::Passwd::touch_userpw_file_if_exists($user);
    Cpanel::ConfigFiles::Apache::vhost::replace_vhost( $parent_domain, undef, $user );

    try {
        Cpanel::Exim::ManualMX::unset_manual_mx_redirects( [$domain] );
    }
    catch {
        warn "Failed to remove $domain’s manual MX: $_";
    };

    Cpanel::HttpUtils::ApRestart::BgSafe::restart();

    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => 'Domain::unpark',
            'stage'    => 'post',
        },
        {
            'domain'        => $domain,
            'parent_domain' => $parent_domain,
            'user'          => $user,
        },
    );

    Cpanel::Userdomains::updateuserdomains();

    # ftpupdate will disable accounts that were on this parked domain
    Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 10, 'ftpupdate' );

    return 1;
}

# XXX Right now this does NOT propagate to a remote node.
sub restore_park {
    return _local_park( @_, 'is_restore' => 1 );
}

sub park (%opts) {
    my $username = $opts{'user'} || die('need “user”');

    my ( $ok, $why );

    $opts{'domain'} ||= _normalize_base_domain( $username, $opts{'domain'} );

    try {
        Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
            username => $username,

            local_action => sub {
                ( $ok, $why ) = _local_park(%opts);
            },

            local_undo => sub {
                my ( $ok, $why ) = _local_unpark(
                    user          => $opts{'user'},
                    domain        => $opts{'newdomain'},
                    parent_domain => $opts{'domain'},
                );

                # Not localized because this is only for admin.
                die "local unpark: $why" if !$ok;
            },

            remote_action => sub ($node_obj) {
                if ($ok) {    # skip if local failed
                    Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                        node_obj => $node_obj,
                        function => 'PRIVATE_create_parked_domain_for_user_on_child',
                        api_opts => {
                            username         => $username,
                            domain           => $opts{'newdomain'},
                            web_vhost_domain => $opts{'domain'},
                        },
                    );
                }
            },

            remote_undo => sub ($node_obj) {
                Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                    node_obj => $node_obj,
                    function => 'delete_domain',
                    api_opts => {
                        domain => $opts{'newdomain'},
                    },
                );
            },
        );
    }
    catch {
        $ok  = 0;
        $why = Cpanel::Exception::get_string_no_id($_);
    };

    return ( $ok, $why );
}

sub _normalize_base_domain ( $username, $domain ) {
    $domain = Cpanel::Validate::Domain::Normalize::normalize($domain) if length $domain;

    return $domain ||= do {
        my $cpuser_hr = Cpanel::Config::LoadCpUserFile::load_or_die($username);
        $cpuser_hr->{'DOMAIN'};
    };
}

sub _local_park {    ## no critic qw(ProhibitExcessComplexity)

    my %OPTS             = @_;
    my $allowoverwrite   = $OPTS{'allowoverwrite'};
    my $domain           = $OPTS{'domain'};
    my $ndomain          = $OPTS{'newdomain'};
    my $skip_ssl_setup   = $OPTS{'skip_ssl_setup'} ? 1 : 0;
    my $user             = $OPTS{'user'};
    my $nodnsreload      = $OPTS{'nodnsreload'};
    my $newdomain_exists = $OPTS{'newdomain_exists'};
    my $no_cache_update  = $OPTS{'no_cache_update'};
    my $is_restore       = $OPTS{'is_restore'};
    my $cpconf           = $OPTS{'cpconf'};
    my $cpuser_ref       = $OPTS{'cpuser_ref'};

    my $domain_registration_validation = $OPTS{'domain_registration_validation'};

    $ndomain =~ s/\*//g;
    $domain  = Cpanel::Validate::Domain::Normalize::normalize($domain) if length $domain;
    $ndomain = Cpanel::Validate::Domain::Normalize::normalize($ndomain);

    my $addonuser;
    if ($domain) {
        ($addonuser) = $domain =~ m{ \A ([^.]+) }xms;
    }

    if ( index( $ndomain, 'www.' ) == 0 ) {
        return ( 0, "The domain '$ndomain' may not contain the 'www.' label." );
    }

    if ( !$user || $user eq '' ) {
        $user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);
        if ( !defined($user) || $user eq '' ) {
            $user = 'root';
        }
    }

    my $userdata = Cpanel::Config::userdata::Load::load_userdata_main($user);
    if ( !defined $userdata || ref $userdata ne 'HASH' ) {
        return ( 0, "Failed to load userdata for '$user'" );
    }
    my $user_domains_ar = Cpanel::Config::userdata::Utils::get_all_domains_from_main_userdata_ar($userdata);

    # XXX FIXME XXX THIS IS AWFUL ZOMG ZOMG MURDERED PUPPIES XXX!!!!!!
    # The “|| q<>” below is to silence a warning that arises here because
    # WHM’s “Park a Domain” UI allows submission without a user selection.
    my $maindomain = $userdata->{'main_domain'} || q<>;
    $domain = $maindomain if !$domain;

    my @domain_registration_system_args;
    if ( ( $domain_registration_validation || q<> ) eq 'none' ) {

        # This makes Cpanel::Validate::Component::Domain::DomainRegistration
        # a no-op if it’s loaded.
        push @domain_registration_system_args, (
            allowremotedomains       => 1,
            allowunregistereddomains => 1,
        );
    }

    {
        my $err_obj;
        if ( $domain eq $maindomain ) {
            try {
                my $parked_domain_creation_validator = Cpanel::Validate::DomainCreation::Parked->new(
                    { 'domain' => $ndomain },
                    {
                        'ownership_user'    => $user,              # The user who will own the domain once it is created.
                        'force'             => $allowoverwrite,
                        'userdata_main_ref' => $userdata,
                        'user_domains_ar'   => $user_domains_ar,

                        ( Cpanel::App::is_whm() ? ( 'validation_context' => Cpanel::Validate::DomainCreation::Parked->VALIDATION_CONTEXTS()->{'WHOSTMGR'} ) : () ),

                        @domain_registration_system_args,
                    }
                );
                $parked_domain_creation_validator->validate();
            }
            catch {
                $err_obj = $_;
            };
        }
        else {
            try {
                my $addon_domain_creation_validator = Cpanel::Validate::DomainCreation::Addon->new(
                    {
                        'domain'        => $ndomain,
                        'target_domain' => $domain
                    },
                    {
                        'ownership_user'    => $user,              # The user who will own the domain once it is created.
                        'force'             => $allowoverwrite,
                        'userdata_main_ref' => $userdata,
                        'user_domains_ar'   => $user_domains_ar,

                        ( Cpanel::App::is_whm() ? ( 'validation_context' => Cpanel::Validate::DomainCreation::Addon->VALIDATION_CONTEXTS()->{'WHOSTMGR'} ) : () ),

                        @domain_registration_system_args,
                    }
                );
                $addon_domain_creation_validator->validate();
            }
            catch {
                $err_obj = $_;
            };
        }
        if ($err_obj) {
            my $message;
            if ( ref $err_obj && $err_obj->isa('Cpanel::Exception') ) {
                Cpanel::Logger::cplog( "Invalid domain [$ndomain]", 'info', __PACKAGE__, 1 ) if $err_obj->isa('Cpanel::Exception::InvalidDomain');
                $message = Cpanel::Encoder::Tiny::safe_html_encode_str( $err_obj->to_locale_string() );
            }
            else {
                $message = Cpanel::Encoder::Tiny::safe_html_encode_str($err_obj);
            }
            return ( 0, $message );
        }
    }

    my $hook_info = {
        'category' => 'Whostmgr',
        'event'    => 'Domain::park',
        'stage'    => 'pre',
        'blocking' => 1,
    };

    my ( $pre_hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        $hook_info,
        {
            'target_domain' => $domain,
            'new_domain'    => $ndomain,
            'user'          => $user,
        },
    );
    return ( 0, Cpanel::Hooks::hook_halted_msg( $hook_info, $hook_msgs ) ) if !$pre_hook_result;

    if ( defined( my $sub_domain = Cpanel::Config::userdata::Load::is_addon_domain( $user, $domain, $userdata ) ) ) {

        # The user selected an addon domain; make the new domain an addon for the same sub-domain
        $logger->info("Creating Addon domain '$ndomain' on '$sub_domain' (user selected '$domain').");
        $domain = $sub_domain;
    }
    elsif ( Cpanel::Config::userdata::Load::is_parked_domain( $user, $domain, $userdata ) ) {

        # The user selected a parked domain; park the new domain on the user's primary domain
        $logger->info("Parking domain '$ndomain' on '$maindomain' (user selected '$domain').");
        $domain = $maindomain;
    }
    elsif ( Cpanel::Config::userdata::is_sub_domain( $user, $domain, $userdata ) ) {

        # The user selected a sub-domain; make the new domain an addon for that sub-domain (leave $domain unchanged)
        # This 'elsif' exists only for logging purposes
        $logger->info("Creating Addon domain '$ndomain' on '$domain'.");
    }

    # Skip the addon domain check since we already set $domain to the vhost
    my $dns_userdata = Cpanel::Config::userdata::Load::load_userdata_domain( $user, $domain, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
    my $ip           = $dns_userdata->{'ip'};

    # Otherwise the user selected a primary domain; park the new domain there (leave $domain unchanged)

    if ( !$ip || !Cpanel::Validate::IP::v4::is_valid_ipv4($ip) ) {
        $ip = Cpanel::DomainIp::getdomainip($maindomain);
        if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($ip) ) {
            $ip = Cpanel::SocketIP::_resolveIpAddress($domain);
            if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($ip) ) {
                return ( 0, "Sorry, cannot resolve $domain to an ip address" );
            }
        }
    }

    $cpuser_ref ||= Cpanel::Config::LoadCpUserFile::load($user);

    # the ipv6 info on the user if applicable -> need this when adding the new domain
    my ( $has_ipv6, $ipv6 ) = Cpanel::IPv6::Normalize::normalize_ipv6_address( Cpanel::IPv6::User::extract_ipv6_from_userdata($dns_userdata) || $cpuser_ref->{'IPV6'} );
    $ipv6 = Cpanel::IPv6::Normalize::DOES_NOT_HAVE_IPV6_STRING() if !$has_ipv6;    # Cpanel::IPv6::Normalize::DOES_NOT_HAVE_IPV6_STRING() is a magical return that is required

    $cpconf ||= Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    require Cpanel::DnsUtils::Add;
    my ( $status, $park_error ) = Cpanel::DnsUtils::Add::doadddns(
        'domain'         => $ndomain,
        'ip'             => $ip,
        'has_ipv6'       => $has_ipv6,
        'ipv6'           => $ipv6,
        'allowoverwrite' => 1,                                  # we would not get here if $allowoverwrite was false or the zone existed
                                                                # so it is safe to skip this check
        'trueowner'      => ( $user ne 'root' ? $user : '' ),
        'is_restore'     => $is_restore                  ? 1 : 0,
        'nodnsreload'    => $cpconf->{'proxysubdomains'} ? 1 : $nodnsreload
    );

    if ( !$status ) {
        return ( 0, $park_error );
    }

    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => 'Domain::park',
            'stage'    => 'post',
        },
        {
            'target_domain' => $domain,
            'new_domain'    => $ndomain,
            'user'          => $user,
        },
    );

    my $target_domain = $domain;

    my $warning_msg = 'Domain was successfully parked.';
    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        Cpanel::Logger::cplog( "User $user not found for $domain", 'info', __PACKAGE__, 1 );
        Cpanel::ConfigFiles::Apache::vhost::replace_vhost( $target_domain, undef, $user );
        Cpanel::HttpUtils::ApRestart::BgSafe::restart();
        return ( 0, "Domain was parked, however an invalid user was specified." );
    }
    else {

        # Update userdata - it may be a parked domain on top of an addon domain, need to switch domain to the sub domain of the parked domain
        $target_domain = Cpanel::Config::userdata::add_parked_domain_data(
            {
                'user'            => $user,
                'parked_domain'   => $ndomain,
                'domain'          => $domain,
                'no_cache_update' => $no_cache_update,
            }
        );

        # doadddns modifies the cpuser file
        Cpanel::MailTools::setupusermaildomainforward(
            'user'      => $user,
            'olddomain' => $domain,
            'newdomain' => $ndomain,
            'nomaildbs' => $is_restore
        );

        my $homeDirectory = Cpanel::PwCache::gethomedir($user);

        # Do not change to Cpanel::hasfeature as it will break WHM
        if ( $cpconf->{'emailarchive'} ) {

            require Cpanel::Email::Archive;

            if ( -e Cpanel::Email::Archive::get_archiving_default_config_file_path($homeDirectory)
                && Cpanel::Features::Check::check_feature_for_user( $user, 'emailarchive', undef, $cpuser_ref ) ) {
                Cpanel::AccessIds::ReducedPrivileges::call_as_user(
                    sub {
                        Cpanel::Email::Archive::apply_archiving_default_configuration( $ndomain, $user, $homeDirectory );
                    },
                    $user
                );
            }
        }

        if ( !$is_restore ) {

            # During a restore all of these actions happen after the Domains.pm module
            Cpanel::ConfigFiles::Apache::vhost::replace_vhost( $target_domain, undef, $user );

            my $owner = Cpanel::AcctUtils::Owner::getowner($user);
            Cpanel::Domains::del_deleted_domains( $user, $owner, '', [$ndomain] );
            if ( $cpconf->{'proxysubdomains'} ) {
                Cpanel::Proxy::setup_proxy_subdomains( domain => $ndomain, domain_owner => $user, skipreload => $nodnsreload, has_ipv6 => $has_ipv6, ipv6 => $ipv6 );
                Cpanel::WebVhosts::ProxySubdomains::sync_base_vhost_if_needed( $user, $ndomain );
            }

            # We need a warning here if we fail, but it's probably not a failing case.
            if ( Cpanel::DKIM::has_dkim( 'user' => $user ) ) {
                my $xaction = Cpanel::DKIM::Transaction->new();

                my @msg;
                my $status = do {
                    local $SIG{'__WARN__'} = sub { push @msg, @_ };
                    $xaction->set_up_user_domains( $user, [$ndomain] );
                };

                $warning_msg = "Domain was parked, DKIM failed (@msg)" unless $status;

                $xaction->commit();
            }
            if ( Cpanel::SPF::has_spf( 'user' => $user ) ) {
                my ( $status, $msg ) = Cpanel::SPF::Update::update_spf_records_for_domains( 'domains' => [$ndomain] );
                unless ($status) {
                    $warning_msg .= "\n" if $warning_msg;
                    $warning_msg .= "Domain was parked, SPF failed ($msg)";
                }
            }

            # Touch the ftp passwd file for the user
            # so that the 'list_ftp' cache is refreshed properly.
            Cpanel::FtpUtils::Passwd::touch_userpw_file_if_exists($user);

            # Update intermediary caches
            # userdomains is updated in doadddns so
            # it does not need to be done here.
            my $email_limits_line = Cpanel::EmailLimits->new()->get_email_send_limit_key( $user, $ndomain );
            Cpanel::TextDB::addline( "$ndomain: $email_limits_line", "/etc/email_send_limits" ) if $email_limits_line;

            Cpanel::HttpUtils::ApRestart::BgSafe::restart();
            Cpanel::Userdomains::updateuserdomains();

            # ftpupdate will disable accounts that were on this parked domain
            Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 10, 'ftpupdate' );
        }
    }

    if ( !$skip_ssl_setup ) {

        # If we create a parked domain do not want to call this function
        # because it will already have an ssl vhost.
        #
        # We expect the caller to pass skip_ssl_setup
        # when creating a parked domain.  It should
        # called for addon domains.
        Cpanel::SSL::Setup::setup_new_domain( 'user' => $user, 'domain' => $domain );
    }

    return ( 1, $warning_msg );
}

1;
