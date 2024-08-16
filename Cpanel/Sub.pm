package Cpanel::Sub;

# cpanel - Cpanel/Sub.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;
use Cwd                                      ();
use Cpanel::App                              ();
use Cpanel::AccessIds::ReducedPrivileges     ();
use Cpanel::AcctUtils::DomainOwner::Tiny     ();
use Cpanel::PwCache                          ();
use Cpanel::AcctUtils::Owner                 ();
use Cpanel::ApacheConf::MailAlias            ();
use Cpanel::Exception                        ();
use Cpanel::Hooks                            ();
use Cpanel::HttpUtils::Conf                  ();
use Cpanel::HttpUtils::Config::Apache        ();
use Cpanel::HttpUtils::ApRestart::BgSafe     ();
use Cpanel::Domain::TLS::Write               ();
use Cpanel::Domain::Zone                     ();
use Cpanel::Features::Check                  ();
use Cpanel::DnsUtils::AskDnsAdmin            ();
use Cpanel::TextDB                           ();
use Cpanel::StringFunc::File                 ();
use Cpanel::FileUtils::Lines                 ();
use Cpanel::MailTools                        ();
use Cpanel::EmailLimits                      ();
use Whostmgr::DNS::Domains                   ();
use Cpanel::Exim::ManualMX                   ();
use Cpanel::Config::LoadCpUserFile           ();
use Cpanel::Config::ModCpUserFile            ();
use Cpanel::Config::LoadCpConf               ();
use Cpanel::Config::userdata::Load           ();
use Cpanel::Config::userdata::Utils          ();
use Cpanel::Config::userdata                 ();
use Cpanel::ConfigFiles                      ();
use Cpanel::PwCache                          ();
use Cpanel::LoadModule                       ();
use Cpanel::SafeDir::Fixup                   ();
use Cpanel::SafeDir::MK                      ();
use Cpanel::IPv6::Normalize                  ();
use Cpanel::FileUtils::Open                  ();
use Cpanel::ServerTasks                      ();
use Cpanel::Domains                          ();
use Cpanel::Debug                            ();
use Cpanel::Validate::DomainCreation::Sub    ();
use Cpanel::Validate::Domain::Normalize      ();
use Cpanel::ConfigFiles::Apache::vhost       ();
use Cpanel::ConfigFiles::Apache::VhostUpdate ();
use Cpanel::DKIM                             ();
use Cpanel::DKIM::Transaction                ();
use Cpanel::SPF                              ();
use Cpanel::SPF::Update                      ();
use Cpanel::SSL::Auto::Exclude::Set          ();
use Cpanel::IPv6::User                       ();
use Cpanel::IPv6::UserDataUtil               ();
use Cpanel::IPv6::UserDataUtil::Key          ();
use Cpanel::FileUtils::Modify                ();
use Cpanel::Userdomains                      ();
use Cpanel::SSL::Setup                       ();
use Whostmgr::Transfers::State               ();
use Cpanel::FtpUtils::Passwd                 ();
use Cpanel::WebVhosts::ProxySubdomains       ();
use Cpanel::WildcardDomain                   ();
use Cpanel::WildcardDomain::Tiny             ();
use Cpanel::Debug                            ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';
use Cpanel::Try                     ();
use Cpanel::LinkedNode::Worker::WHM ();

our $VERSION       = '1.5';
our $SQLITE_NOTADB = 26;

# XXX Please don’t call this function directly; instead, look at
# Cpanel::SubDomain::Create.
sub addsubdomain {
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    return _create_subdomain_on_all_nodes(
        @_,
        cpconf => $cpconf,
    );
}

#This is to be called from account restorations.
# XXX Right now this does NOT propagate to a remote node.
sub restore_subdomain {
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    local $cpconf->{'publichtmlsubsonly'} = 0;

    return _create_local_subdomain(
        @_,
        cpconf     => $cpconf,
        is_restore => 1,
    );
}

sub _create_subdomain_on_all_nodes (%opts) {

    my $username = $opts{'user'}         || die('need “user”');
    my $docroot  = $opts{'documentroot'} || die 'need “documentroot”';
    my $cpconf   = $opts{'cpconf'}       || die 'need “cpconf”';

    # The local logic massages an invalid input, whereas the remote API call
    # rejects anything that looks wrong. So we need to massage the input,
    # then convert that to a relative directory as the remote API requires.

    my $local_docroot = _normalize_docroot_for_local( $cpconf, $username, $docroot );
    my $homedir       = Cwd::abs_path( Cpanel::PwCache::gethomedir($username) );

    my $relative_docroot = $local_docroot;
    $relative_docroot =~ s<\A\Q$homedir\E/><> or do {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid document root.', $docroot );
    };

    my ( $ok, $why );

    my $full_domain = join( '.', @opts{ 'subdomain', 'rootdomain' } );

    Cpanel::Try::try(
        sub {
            Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
                username => $username,

                local_action => sub {
                    ( $ok, $why ) = _create_local_subdomain(%opts);
                },

                local_undo => sub {
                    my ( $ok, $why ) = _delete_local_subdomain( %opts{ 'user', 'rootdomain', 'subdomain' } );

                    # Not localized because this is an admin-level error only.
                    die "local delsubdomain: $why" if !$ok;
                },

                remote_action => sub ($node_obj) {
                    return if !$ok;    # skip if local failed

                    Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                        node_obj => $node_obj,
                        function => 'create_subdomain',
                        api_opts => {
                            domain             => $full_domain,
                            document_root      => $relative_docroot,
                            use_canonical_name => !$opts{'usecannameoff'},
                        },
                    );
                },

                remote_undo => sub ($node_obj) {
                    Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                        node_obj => $node_obj,
                        function => 'delete_domain',
                        api_opts => {
                            domain => $full_domain,
                        },
                    );
                },
            );
        },
        'Cpanel::Exception' => sub {
            my $err = $@;

            $ok  = 0;
            $why = $err->to_string_no_id();
        },
        q<> => sub {
            $ok  = 0;
            $why = "$@";
        },
    );

    return ( $ok, $why );
}

sub _normalize_docroot_for_local ( $cpconf, $username, $given_docroot ) {

    # IMPORTANT: Ensure that Cpanel::Validate::DocumentRoot
    # rejects everything that this logic coerces out.
    if ($given_docroot) {
        $given_docroot =~ s/\\//g;
        $given_docroot =~ tr{/}{}s;    # collapse //s to /
        $given_docroot =~ tr{<>}{}d;
    }

    my $home     = Cpanel::PwCache::gethomedir($username);
    my $abs_home = Cwd::abs_path($home);

    my $subroot;
    if ( $cpconf->{'publichtmlsubsonly'} ) {
        $subroot = Cpanel::SafeDir::Fixup::publichtmldirfixup( $given_docroot, $home, $abs_home );
    }
    else {
        $subroot = Cpanel::SafeDir::Fixup::homedirfixup( $given_docroot, $home, $abs_home );
    }

    $subroot =~ s/\*//g;
    $subroot =~ s/\/$//g;

    return $subroot;
}

sub _create_local_subdomain {    ## no critic qw(ProhibitExcessComplexity)
    my %OPTS            = @_;
    my $force           = $OPTS{'force'};
    my $rootdomain      = $OPTS{'rootdomain'};
    my $subdomain       = $OPTS{'subdomain'};
    my $canoff          = $OPTS{'usecannameoff'};
    my $skip_ssl_setup  = $OPTS{'skip_ssl_setup'} ? 1 : 0;
    my $dir             = $OPTS{'documentroot'};
    my $user            = $OPTS{'user'};
    my $nodnsreload     = $OPTS{'nodnsreload'};
    my $skip_conf       = exists $OPTS{'skip_conf_rebuild'} ? $OPTS{'skip_conf_rebuild'} : 1;    #default is now to skip since we add the vhost ourselves now
    my $skip_ap_restart = $OPTS{'skip_restart_apache'} || 0;
    my $no_cache_update = $OPTS{'no_cache_update'}     || 0;
    my $cpconf          = $OPTS{'cpconf'};
    my $cpuser_ref      = $OPTS{'cpuser_ref'};
    my $is_restore      = $OPTS{'is_restore'};

    if ( !defined $rootdomain || !defined $subdomain || !defined $user ) {
        return ( 0, 'Missing user, rootdomain, or subdomain field' );
    }

    my $iswildcard = 0;

    my $fullsubdomain = $subdomain . '.' . $rootdomain;

    if ( $subdomain =~ tr{*}{} ) { $canoff = 1; $iswildcard = 1; }

    $fullsubdomain = Cpanel::Validate::Domain::Normalize::normalize_wildcard($fullsubdomain);

    my @SPLITFULLDOMAIN = split( /\./, $fullsubdomain );
    my $first_label     = shift(@SPLITFULLDOMAIN);
    my $parent_domain   = join( '.', @SPLITFULLDOMAIN );

    Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};
    my $locale = Cpanel::Locale->get_handle();
    if ( Whostmgr::Transfers::State::is_transfer() ) {
        $locale->cpanel_reinit_lexicon();
    }

    # From ParkAdmin to feed the Cpanel::Validate::DomainCreation::Sub
    # as it prevent multiple reloads
    my $userdata = Cpanel::Config::userdata::Load::load_userdata_main($user);
    if ( !defined $userdata || ref $userdata ne 'HASH' ) {
        return ( 0, "Failed to load userdata for '$user'" );
    }

    my $user_domains_ar = Cpanel::Config::userdata::Utils::get_all_domains_from_main_userdata_ar($userdata);

    {
        my $err_obj;
        try {
            my $subdomain_creation_validator = Cpanel::Validate::DomainCreation::Sub->new(
                {
                    'sub_domain'    => $first_label,
                    'target_domain' => $parent_domain,
                    'root_domain'   => $rootdomain,
                },
                {
                    'force'             => $force,
                    'ownership_user'    => $user,
                    'main_userdata_ref' => $userdata,
                    'user_domains_ar'   => $user_domains_ar,
                    ( Cpanel::App::is_whm() ? ( 'validation_context' => Cpanel::Validate::DomainCreation::Sub->VALIDATION_CONTEXTS()->{'WHOSTMGR'} ) : () )
                }
            );
            $subdomain_creation_validator->validate();
        }
        catch {
            $err_obj = $_;
        };
        if ($err_obj) {
            if ( ref $err_obj && $err_obj->isa('Cpanel::Exception') ) {
                return ( 0, $err_obj->to_locale_string() );
            }
            else {
                return ( 0, $err_obj );
            }
        }
    }

    # If the parsed parent domain is not the same as the root domain passed in,
    # and it has its own zone file, then use the parent domain's zone file when
    # adding records.
    local $@;
    my $recalc_ok = eval { ( $subdomain, $rootdomain ) = _recalc_subdomain_and_root_domain_based_on_existing_zonefiles( $subdomain, $rootdomain ); };
    if ( !$recalc_ok ) {
        return ( 0, "$@" );
    }

    my $hook_info = {
        'category' => 'Whostmgr',
        'event'    => 'Domain::addsubdomain',
        'stage'    => 'pre',
        'blocking' => 1,
    };

    my ( $pre_hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        $hook_info,
        {
            'user'       => $user,
            'subdomain'  => $subdomain,
            'rootdomain' => $rootdomain,
        },
    );
    return ( 0, Cpanel::Hooks::hook_halted_msg( $hook_info, $hook_msgs ) ) if !$pre_hook_result;

    $cpuser_ref ||= Cpanel::Config::LoadCpUserFile::load($user);

    # Deal with the case where it is ipv6.domain when we have ipv6
    Cpanel::IPv6::UserDataUtil::fix_possible_new_domain_issues( $user, $first_label );

    my ( $gid, $home ) = ( Cpanel::PwCache::getpwnam_noshadow($user) )[ 3, 7 ];
    my $abs_home = Cwd::abs_path($home);

    my $currentip;
    my $dns_userdata = Cpanel::Config::userdata::Load::load_userdata_real_domain( $user, $rootdomain, $userdata );
    if ($dns_userdata) {
        $currentip = $dns_userdata->{'ip'};
    }
    if ( !$currentip && !$skip_conf ) {
        return ( 0, "We were unable to locate your current domain name, $parent_domain in the webserver configuration!  The subdomain cannot be added because information about your domain could not be obtained from the webserver configuration file." );
    }

    # the ipv6 info on the user if applicable -> need this when adding the new domain
    my ( $has_ipv6, $ipv6 ) = Cpanel::IPv6::Normalize::normalize_ipv6_address( Cpanel::IPv6::User::extract_ipv6_from_userdata($dns_userdata) || $cpuser_ref->{'IPV6'} );
    $ipv6 = Cpanel::IPv6::Normalize::DOES_NOT_HAVE_IPV6_STRING() if !$has_ipv6;    # Cpanel::IPv6::Normalize::DOES_NOT_HAVE_IPV6_STRING() is a magical return that is required

    my ( $status, $cip );

    unless ($is_restore) {

        # HERE WE ARE ADDING THE DNS ENTRY
        ( $status, $cip ) = Whostmgr::DNS::Domains::addsubdomain(
            '', '', '', '',
            {

                # if proxydomains is enabled we'll let the reload happen when they get added
                'nodnsreload'    => 1,
                'sub'            => $subdomain,
                'adviseip'       => $currentip,
                'allowoverwrite' => $force,
                'domain'         => $rootdomain . '.db',
                'addwww'         => 1,
                'readd'          => 1,
                'cpanel'         => 1,
                'has_ipv6'       => $has_ipv6,
                'ipv6'           => $ipv6,
            }
        );
        return ( 0, $cip ) unless $status;
    }

    my $ip = $cip || $currentip;

    my $subroot = _normalize_docroot_for_local( $cpconf, $user, $dir );

    my $hascgi = $cpuser_ref->{'HASCGI'};

    # Update userdata
    my %input;
    $input{'user'}                  = $user;
    $input{'homedir'}               = $home;
    $input{'group'}                 = ( getgrgid($gid) )[0];
    $input{'sub_domain'}            = $fullsubdomain;
    $input{'servername'}            = $fullsubdomain;
    $input{'serveralias'}           = 'www.' . $fullsubdomain if ( $fullsubdomain !~ m{ \A  [*] }xms );
    $input{'serveradmin'}           = 'webmaster@' . ( $fullsubdomain !~ m{ \A [*] }xms ? $fullsubdomain : $parent_domain );
    $input{'documentroot'}          = $subroot;
    $input{'usecanonicalname'}      = $canoff ? 'Off' : 'On';
    $input{'phpopenbasedirprotect'} = Cpanel::HttpUtils::Conf::fetchphpopendirconf( $user, $fullsubdomain );
    $input{'ip'}                    = $ip;
    $input{'hascgi'}                = $hascgi;
    $input{'owner'}                 = $cpuser_ref->{'OWNER'} || 'root';
    $input{'no_cache_update'}       = $no_cache_update;

    $input{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key} = $dns_userdata->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key};

    my @userdirprotect = Cpanel::HttpUtils::Conf::fetchdirprotectconf($fullsubdomain);
    $input{'userdirprotect'} = ( !$userdirprotect[0] ) ? '-1' : $userdirprotect[1];

    # We start making modifications here

    # Set up domlogs with correct permissions instead of letting Apache handle it
    my $domlog = apache_paths_facade->dir_domlogs() . '/' . Cpanel::WildcardDomain::encode_wildcard_domain($fullsubdomain);
    {
        Cpanel::FileUtils::Open::sysopen_with_real_perms( my $fh, $domlog, 'O_WRONLY|O_APPEND|O_CREAT', 0640 );
        chown( 0, $gid, $fh );
        chmod 0640, $fh;
    }

    Cpanel::Config::userdata::add_sub_domain_data( \%input );

    # We now autoadd the mail alias in the userdata for a domain, but this can block the creation of a mail.domain.tld subdomain
    # if we don't remove it from the parent domain's vhost before trying to create the subdomain vhost, the subdomain vhost additon will fail.
    if ( $first_label eq 'mail' ) {
        Cpanel::ApacheConf::MailAlias::remove_mail_subdomain_for_user_domain( $user, $rootdomain );
    }

    if ( !$is_restore ) {
        my $undo_userdata_and_domlog_cr = sub {

            # Remove log files created that had nothing written to them
            unlink $domlog if -z $domlog;

            # Roll back the changes if adding the vhost fails
            Cpanel::Config::userdata::remove_sub_domain_data( { 'user' => $user, 'sub_domain' => $fullsubdomain } );
            Cpanel::ApacheConf::MailAlias::add_mail_subdomain_for_user_domain( $user, $rootdomain ) if $first_label eq 'mail';
        };

        # If we are not in a restore we need to recreate the vhosts in httpd.conf
        # so do_vhost will fail. If its a restore it doesn't matter since the vhost
        # does not yet exist.
        if ( $first_label eq 'mail' ) {
            my ( $status, $message ) = Cpanel::ConfigFiles::Apache::vhost::replace_vhosts( [ { 'current_domain' => $rootdomain, 'owner' => $user } ] );
            if ( !$status ) {

                $undo_userdata_and_domlog_cr->();
                return ( $status, $message );
            }
        }
        else {
            #Remove the service (formerly proxy) subdomains from the base vhost first so that we can
            #add them in the new vhost.
            #
            #This takes the *subdomain*. Not the base domain.
            #It then examines whether the passed-in domain is a proxy
            #and updates the base domain’s vhost accordingly.
            Cpanel::WebVhosts::ProxySubdomains::sync_base_vhost_if_needed( $user, $fullsubdomain );
        }

        # During a restore all of these actions happen after the Domains.pm module
        my ( $status, $message ) = Cpanel::ConfigFiles::Apache::VhostUpdate::do_vhost( $fullsubdomain, $user );

        if ( !$status ) {

            $undo_userdata_and_domlog_cr->();
            return ( $status, $message );
        }

        my $needs_ensure_vhost_includes = 0;

        #
        # If we add another vhost include that requires a .conf file to be
        # created to be used during subdomain creation time then we should uncomment
        # the $needs_ensure_vhost_includes line below. Currently, all the include config files
        # are all domain or user specific. So there is no need to look for a vhost include
        # config file since user specific ones will already be included and since this domain
        # is new there will be no domain config.
        #
        # $needs_ensure_vhost_includes = 1;
        #
        if ($needs_ensure_vhost_includes) {
            my @vhost_args = ( '--domain=' . $fullsubdomain, '--no-restart' );
            push @vhost_args, '--skip-conf-rebuild' if $skip_conf;
            push @vhost_args, '--domain-owner=' . $user;

            # For profiling
            #chdir '/root';
            #system 'perl','-d:NYTProf','/usr/local/cpanel/scripts/ensure_vhost_includes', @vhost_args;
            system '/usr/local/cpanel/scripts/ensure_vhost_includes', @vhost_args;
        }
    }

    # Setup new directories
    _ensure_docroot_exists( $subroot, $user, $hascgi );

    # Add mail configuration
    Cpanel::MailTools::setupusermaildomainforward(
        'user'      => $user,
        'newdomain' => $fullsubdomain,
        'nomaildbs' => $is_restore,
    );

    # Touch the ftp passwd file for the user
    # so that the 'list_ftp' cache is refreshed properly.
    Cpanel::FtpUtils::Passwd::touch_userpw_file_if_exists($user);

    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => 'Domain::addsubdomain',
            'stage'    => 'post',
        },
        {
            'user'       => $user,
            'subdomain'  => $subdomain,
            'rootdomain' => $rootdomain,
        },
    );

    my $domain_added_message = $locale->maketext( 'The subdomain “[_1]” has been added.', $fullsubdomain );

    # We must always add to /etc/userdomains even on a restore since
    # Cpanel::Domain::Zone needs this entry for subdomain on top of
    # subdomains.  This will get blown away the next time we run
    # updateuserdomains and that is OK
    Cpanel::FileUtils::Lines::appendline( "/etc/userdomains", "$fullsubdomain: $user" );

    if ( !$is_restore ) {
        try {
            _bwdb_init_subdomain( $user, $fullsubdomain );    # will throw Cpanel::Exception::Database::Error if there is a problem with the main domain bw database
        }
        catch {
            my $error_obj  = $_;
            my $error      = $error_obj->get('error_code') // q{};
            my $dbi_driver = $error_obj->get('dbi_driver') // q{};
            my $db_file    = $error_obj->get('database')   // q{};
            _check_for_corrupt_database_and_tryagain( $error, $dbi_driver, $db_file, $user, $fullsubdomain );
        };

        # Update cPanel user file
        Cpanel::Config::ModCpUserFile::adddomaintouser(
            'user'   => $user,
            'domain' => $fullsubdomain,
            'type'   => ''
        );    #this will remove the deleted domain if it exist

        Cpanel::Domains::del_deleted_domains( $user, 'root', '', [$fullsubdomain] );

        my $email_limits_line = Cpanel::EmailLimits->new()->get_email_send_limit_key( $user, $fullsubdomain );
        Cpanel::TextDB::addline( "$fullsubdomain: $email_limits_line", "/etc/email_send_limits" ) if $email_limits_line;

        Cpanel::Userdomains::updateuserdomains();    # must happen before DKIM

        if ( Cpanel::DKIM::has_dkim( user => $user ) ) {

            # Failure to add DKIM used to be fatal, but that was excessive.
            my $dkim = Cpanel::DKIM::Transaction->new()->skip_dns_reloads();
            $dkim->set_up_user_domains( $user, [$fullsubdomain] );
            $dkim->commit();
        }

        # Likely not adding SPF should be a warning instead of a failure
        # For now we just show that the subdomain was added but there was
        # a failure

        if ( Cpanel::SPF::has_spf( user => $user ) ) {
            my ( $status, $msg ) = Cpanel::SPF::Update::update_spf_records_for_domains( 'domains' => [$fullsubdomain], 'reload' => 0 );
            return ( 0, $domain_added_message . ': ' . "Unable to set up SPF for '$fullsubdomain': $msg" ) if $status != 1;
        }

        # case CPANEL-16178: Ensure DNS is reloaded when setting up DKIM, SPF, service (formerly proxy) subs
        # Add proxy domains if required, must be after DKIM and SPF as it triggers the dns reload
        if (
            # CPANEL-18666: If the domain is a wildcard Cpanel::Proxy::setup_proxy_subdomains subdomains will do not
            # nothing and the zone will not be reloaded so must not enter this block and continue
            # down the if block to see if we need to reload the zones
            $fullsubdomain !~ tr{*}{} && $cpconf->{'proxysubdomains'}
        ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Proxy');
            Cpanel::Proxy::setup_proxy_subdomains( domain => $fullsubdomain, domain_owner => $user, skipreload => $nodnsreload, has_ipv6 => $has_ipv6, ipv6 => $ipv6 );
        }
        elsif ( !$nodnsreload ) {
            Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin(
                'RELOADZONES',                                                                        #
                0,                                                                                    #
                $fullsubdomain =~ tr{*}{} ? $rootdomain : join( ',', $rootdomain, $fullsubdomain )    #
            );
        }

        if ( !$skip_ap_restart ) {

            # Restart Apache
            Cpanel::HttpUtils::ApRestart::BgSafe::restart();
        }

        if ( !$skip_ssl_setup ) {

            # If we create an addon domain we do not want to call this function
            # because it will setup an ssl certificate twice.
            Cpanel::SSL::Setup::setup_new_domain( 'user' => $user, 'domain' => $fullsubdomain, 'subdomain' => 1 );
        }

        require Cpanel::FileProtect::Queue::Adder;

        # Enable fileprotect on subdomain directories if appropriate
        Cpanel::FileProtect::Queue::Adder->add($user);
        Cpanel::ServerTasks::schedule_task( ['FileProtectTasks'], 5, 'fileprotect_sync_user_homedir' );

        # ftpupdate will reenable accounts that were on this subdomain
        Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 10, 'ftpupdate' );

    }

    if ( $cpconf->{'emailarchive'} ) {
        require Cpanel::Email::Archive;
        if ( -e Cpanel::Email::Archive::get_archiving_default_config_file_path($home)
            && Cpanel::Features::Check::check_feature_for_user( $user, 'emailarchive', undef, $cpuser_ref ) ) {
            Cpanel::AccessIds::ReducedPrivileges::call_as_user(
                sub {
                    Cpanel::Email::Archive::apply_archiving_default_configuration( $fullsubdomain, $user, $home );
                },
                $user
            );
        }
    }

    return ( 1, $domain_added_message );
}

sub _check_for_corrupt_database_and_tryagain {
    my ( $error, $dbi_driver, $db_file, $user, $fullsubdomain ) = @_;

    # if SQLITE corrupted file detected, move aside, generate a new one, then retry (just once)
    if ( $error == $SQLITE_NOTADB and $dbi_driver eq q{SQLite} ) {

        #1. move corrupted file out of the way, this will overwrite any existing $db_file.corrupted
        my $db_file_corrupted = qq{$db_file.corrupted};

        rename( $db_file, $db_file_corrupted ) or do {
            Cpanel::Debug::log_warn("“$db_file” is corrupt. Recreation attempt failed: rename($db_file => $db_file_corrupted): $!");
            return;
        };

        #2. retrun "initialize_domain" once; Cpanel::Exception here will rise beyond here bc
        #the problem is much bigger than a corrupt bw database; since $db_file no longer exists,
        #this call implicitly recreates it when missing
        _bwdb_init_subdomain( $user, $fullsubdomain );

        #3. write warning to log
        Cpanel::Debug::log_warn(qq{Recreated $db_file because it was corrupted. The old file was saved as $db_file_corrupted.});
    }
    return;
}

# will throw a Cpanel::Exception if there is an issue opening/writing to the database in question
sub _bwdb_init_subdomain {
    my ( $user, $fullsubdomain ) = @_;
    require Cpanel::BandwidthDB;
    my $bwdb = Cpanel::BandwidthDB::get_writer($user);
    if ( !$bwdb->has_domain($fullsubdomain) ) {
        $bwdb->initialize_domain($fullsubdomain);
    }
    return;
}

sub _del_www_part_of_subdomain {
    my ( $subpart, $dns_zone, $force_yn ) = @_;

    #This “special” function will, in fact, *delete* because of the
    #combination of flags here. We only want to delete the “www” part
    #because we want to keep the “mail” part.
    return Whostmgr::DNS::Domains::addsubdomain(
        '', '', '', '',
        {
            'do_not_create_zone' => 1,
            'sub'                => "www.$subpart",
            'allowoverwrite'     => $force_yn,
            'domain'             => "$dns_zone.db",
            'addwww'             => 0,
            'readd'              => 0,
            'cpanel'             => 1,
        },
    );
}

sub delsubdomain (%opts) {
    my $username = $opts{'user'} || die('need “user”');

    my ( $ok, $why );

    my $full_domain = join( '.', @opts{ 'subdomain', 'rootdomain' } );

    Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
        username => $username,

        local_action => sub {
            ( $ok, $why ) = _delete_local_subdomain(%opts);
        },

        remote_action => sub ($node_obj) {
            return if !$ok;    # skip if local failed

            warn if !eval {
                Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                    node_obj => $node_obj,
                    function => 'delete_domain',
                    api_opts => {
                        domain => $full_domain,
                    },
                );
            };
        },
    );

    return ( $ok, $why );
}

sub _delete_local_subdomain {
    my %OPTS            = @_;
    my $user            = $OPTS{'user'};
    my $subdomain       = $OPTS{'subdomain'};
    my $rootdomain      = $OPTS{'rootdomain'};
    my $force           = $OPTS{'force'};
    my $skip_ap_restart = $OPTS{'skip_restart_apache'} || 0;
    my $skip_phpfpm     = $OPTS{'skip_phpfpm'}         || 0;

    if ( !defined $rootdomain || !defined $subdomain || !defined $user ) {
        return ( 0, 'Missing user, root domain, or subdomain field' );
    }

    my $fullsubdomain   = $subdomain . '.' . $rootdomain;
    my @SPLITFULLDOMAIN = split( /\./, $fullsubdomain );
    my $first_label     = shift(@SPLITFULLDOMAIN);

    unless ($skip_phpfpm) {
        Cpanel::LoadModule::load_perl_module('Cpanel::PHPFPM');    # TODO: TaskQueue this
        Cpanel::PHPFPM::_removedomain($fullsubdomain);
    }

    # If the parsed parent domain is not the same as the root domain passed in,
    # and it has its own zone file, then use the parent domain's zone file when
    # removing records.
    local $@;
    my $recalc_ok = eval {
        ( $subdomain, $rootdomain ) = _recalc_subdomain_and_root_domain_based_on_existing_zonefiles( $subdomain, $rootdomain );
        1;
    };
    if ( !$recalc_ok ) {
        return ( 0, "$@" );
    }

    # Case 45043: check subdomain with the full name actually exists or think
    # that it might be an orphaned subdomain
    my %subdomain_list = Cpanel::Config::userdata::load_user_subdomains($user);
    unless ( exists $subdomain_list{$fullsubdomain} ) {
        if ( exists $subdomain_list{$subdomain} && Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($subdomain) eq $user ) {
            $fullsubdomain = $subdomain;
        }
        else {
            return ( 0, "subdomain '$fullsubdomain' does not exist for user '$user'" );
        }
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};
    my $locale = Cpanel::Locale->get_handle();

    if ( $fullsubdomain =~ /^www\./i ) {
        return ( 0, $locale->maketext('The system cannot change the master entry ([asis,www]).') );
    }

    my $hook_info = {
        'category' => 'Whostmgr',
        'event'    => 'Domain::delsubdomain',
        'stage'    => 'pre',
        'blocking' => 1,
    };

    my ( $pre_hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        $hook_info,
        {
            'user'       => $user,
            'subdomain'  => $subdomain,
            'rootdomain' => $rootdomain,
        },
    );
    return ( 0, Cpanel::Hooks::hook_halted_msg( $hook_info, $hook_msgs ) ) if !$pre_hook_result;

    Cpanel::SSL::Auto::Exclude::Set::remove_user_excluded_domains_before_non_main_domain_removal( user => $user, remove_domain => $fullsubdomain );

    Cpanel::MailTools::removedomain($fullsubdomain);
    Cpanel::Config::ModCpUserFile::adddomaintouser(
        'user'   => $user,
        'domain' => $fullsubdomain,
        'type'   => 'X'
    );    #this will also remove the live domain if it exists

    my $owner = Cpanel::AcctUtils::Owner::getowner($user);
    Cpanel::Domains::add_deleted_domains( $user, $owner, '', [$fullsubdomain] );

    #TODO: Handle failures from this.
    _remove_virtual_host_entries_from_apache_configuration($fullsubdomain);

    my $dkim = Cpanel::DKIM::Transaction->new()->skip_dns_reloads();
    $dkim->tear_down_user_domains( $user, [$fullsubdomain] );
    $dkim->commit();

    Cpanel::SPF::remove_a_domains_spf( 'domain' => $fullsubdomain, 'skipreload' => 1 );

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    if ( $cpconf->{'proxysubdomains'} ) {

        # There may be ipv6 info we need to remove
        my ( $has_ipv6, $ipv6 ) = Cpanel::IPv6::User::get_user_ipv6_address($user);

        Cpanel::LoadModule::load_perl_module('Cpanel::Proxy');
        Cpanel::Proxy::setup_proxy_subdomains( 'domain' => $fullsubdomain, 'domain_owner' => $user, 'skipreload' => 1, 'delete' => 1, 'has_ipv6' => $has_ipv6, 'ipv6' => $ipv6 );
    }

    my ( $dns_status, $cip );
    if ( $first_label eq 'mail' ) {
        _del_www_part_of_subdomain( $subdomain, $rootdomain, $force );
    }
    else {
        ( $dns_status, $cip ) = Whostmgr::DNS::Domains::delsubdomain( $rootdomain, $subdomain, $force );

        if ( !$dns_status ) {
            $cip //= q<>;
            Cpanel::Debug::log_warn("Failed to remove the entry for the subdomain “$subdomain” in the DNS zone “$rootdomain”: $cip.");
        }
    }

    # Touch the ftp passwd file for the user
    # so that the 'list_ftp' cache is refreshed properly.
    Cpanel::FtpUtils::Passwd::touch_userpw_file_if_exists($user);

    # CPANEL-42325 - Remove subdomain from FTP passwd file
    Cpanel::StringFunc::File::remlinefile_strict( "$Cpanel::ConfigFiles::FTP_PASSWD_DIR/$user", "\@$fullsubdomain:" );

    # Case 92825 take special care with userdomains
    Cpanel::FileUtils::Modify::remlinefile( '/etc/userdomains', "$fullsubdomain:", 'begin' );

    #Read from the SSL userdata so we know which Domain TLS entries to delete.
    my $old_ssl_ud = Cpanel::Config::userdata::Load::load_ssl_domain_userdata(
        $user,
        $fullsubdomain,
    );

    # Update userdata
    Cpanel::Config::userdata::remove_sub_domain_data( { 'user' => $user, 'sub_domain' => $fullsubdomain } );

    #When we shipped v60, we added this logic for auto-adding “mail.”
    #subdomains as they’re in DNS. Then we found out that some customers
    #actually have already created those domains as subdomains. The below
    #will add in the alias whenever a user deletes such a subdomain.
    if ( $first_label eq 'mail' ) {

        #Clear the cache because we’ll likely have already ascertained
        #domain ownership, which can prevent addition of the new alias.
        Cpanel::AcctUtils::DomainOwner::Tiny::clearcache();

        Cpanel::ApacheConf::MailAlias::add_mail_subdomain_for_user_domain( $user, $rootdomain );

        Cpanel::ConfigFiles::Apache::VhostUpdate::do_vhost( $rootdomain, $user );
    }
    else {

        #This takes the *subdomain*. Not the base domain.
        #It then examines whether the passed-in domain is a proxy
        #and updates the base domain’s vhost accordingly.
        my $needed_yn = Cpanel::WebVhosts::ProxySubdomains::sync_base_vhost_if_needed( $user, $fullsubdomain );

        if ($needed_yn) {
            Whostmgr::DNS::Domains::addsubdomain(
                (q<>) x 4,
                {
                    domain             => "$rootdomain.db",
                    sub                => $subdomain,
                    addwww             => 0,
                    readd              => 1,
                    do_not_create_zone => 1,
                    cpanel             => 1,
                }
            );
        }
    }

    Cpanel::StringFunc::File::remlinefile( '/etc/email_send_limits', "$fullsubdomain:", 'begin' );

    require Cpanel::SMTP::GetMX::Cache;
    Cpanel::SMTP::GetMX::Cache::delete_cache_for_domains( [$fullsubdomain] );

    my $removed;

    if ( $old_ssl_ud && %$old_ssl_ud ) {
        for my $d ( Cpanel::Config::userdata::Utils::get_all_vhost_domains_from_vhost_userdata($old_ssl_ud) ) {
            try {
                my $did_sth = Cpanel::Domain::TLS::Write->enqueue_unset_tls($d);
                $removed ||= $did_sth;
            }
            catch {
                warn "Removing “$d” from Domain TLS: $_";
            };
        }
    }

    if ($removed) {
        Cpanel::ServerTasks::schedule_task( ['DovecotTasks'], 120, 'build_mail_sni_dovecot_conf', 'reloaddovecot' );
    }

    # Deal with the case where it is ipv6.domain when we have ipv6
    Cpanel::IPv6::UserDataUtil::fix_possible_remove_domain_issues( $user, $subdomain );

    # Wildcard domains can’t have manual-MX entries.
    if ( !Cpanel::WildcardDomain::Tiny::is_wildcard_domain($fullsubdomain) ) {
        try {
            Cpanel::Exim::ManualMX::unset_manual_mx_redirects( [$fullsubdomain] );
        }
        catch {
            warn "Failed to remove $fullsubdomain’s manual MX: $_";
        };
    }

    Cpanel::HttpUtils::ApRestart::BgSafe::restart() unless $skip_ap_restart;

    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => 'Domain::delsubdomain',
            'stage'    => 'post',
        },
        {
            'user'       => $user,
            'subdomain'  => $subdomain,
            'rootdomain' => $rootdomain,
        },
    );

    Cpanel::Userdomains::updateuserdomains();

    # ftpupdate will disable accounts that were on this subdomain
    Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 10, 'ftpupdate' );

    return ( 1, $locale->maketext( 'The subdomain “[_1]” has been removed.', $fullsubdomain ) );
}

# This was put into a function to ease mock testing
sub _remove_virtual_host_entries_from_apache_configuration {
    my ($fullsubdomain) = @_;

    my $transaction = eval { Cpanel::HttpUtils::Config::Apache->new() };
    return ( 0, $@ ) if !$transaction;

    my ( $ok, $msg ) = $transaction->remove_vhosts_by_name($fullsubdomain);
    return ( 0, $msg ) if !$ok;

    ( $ok, $msg ) = $transaction->remove_vhosts_by_name( $fullsubdomain, 'ssl' );
    return ( 0, $msg ) if !$ok;

    ( $ok, $msg ) = $transaction->save();
    return ( 0, $msg ) if !$ok;

    ( $ok, $msg ) = $transaction->close();
    return ( 0, $msg ) if !$ok;

    return 1;
}

sub _ensure_docroot_exists {
    my ( $docroot, $user, $hascgi ) = @_;

    require Whostmgr::Accounts::Create::Utils;

    if ( !-e $docroot || ( $hascgi && !-e $docroot . '/cgi-bin' ) ) {
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub {
                Cpanel::SafeDir::MK::safemkdir( $docroot,              '0755' ) if !-e $docroot;
                Cpanel::SafeDir::MK::safemkdir( $docroot . '/cgi-bin', '0755' ) if ( $hascgi && !-e $docroot . '/cgi-bin' );

                Whostmgr::Accounts::Create::Utils::copy_error_docs_to_docroot($docroot);

                return 1;
            },
            $user,
            $user
        );
    }
    return;
}

sub change_doc_root {
    my %OPTS            = @_;
    my $domain          = $OPTS{'domain'};                     # This is the full subdomain dns name ie sub.domain.tld
    my $dir             = $OPTS{'documentroot'};
    my $user            = $OPTS{'user'};
    my $skip_ap_restart = $OPTS{'skip_restart_apache'} || 0;

    if ( !defined $dir || !defined $domain || !defined $user ) {
        return ( 0, 'Missing user, domain or documentroot field' );
    }

    if ( length($dir) > 4096 ) {
        return ( 0, 'Documentroot length exceeds PATH_MAX' );
    }

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    my ( $gid, $home ) = ( Cpanel::PwCache::getpwnam($user) )[ 3, 7 ];
    my $abs_home = Cwd::abs_path($home);

    # IMPORTANT: Ensure that Cpanel::Validate::DocumentRoot
    # rejects everything that this logic coerces out.
    my $subroot = $cpconf->{'publichtmlsubsonly'} ? Cpanel::SafeDir::Fixup::publichtmldirfixup( $dir, $home, $abs_home ) : Cpanel::SafeDir::Fixup::homedirfixup( $dir, $home, $abs_home );

    if ( Cpanel::Config::userdata::change_docroot( { 'domain' => $domain, 'docroot' => $subroot, 'user' => $user } ) ) {

        my ( $status, $message ) = Cpanel::ConfigFiles::Apache::vhost::replace_vhost( $domain, undef, $user );

        if ( !$status ) {
            return ( $status, $message );
        }

        if ( !$skip_ap_restart ) {

            # Restart Apache
            Cpanel::HttpUtils::ApRestart::BgSafe::restart();
        }

        return ( 1, $message );
    }
    return ( 0, "Failed to update userdata" );
}

sub _recalc_subdomain_and_root_domain_based_on_existing_zonefiles {
    my ( $subdomain, $rootdomain ) = @_;

    # No need to do this if we are adding a subdomain
    # on a top level domain with only one dot
    if ( $rootdomain =~ tr{.}{} == 1 && index( $subdomain, '.' ) == -1 ) {
        return ( $subdomain, $rootdomain );
    }

    my $zone_obj            = Cpanel::Domain::Zone->new();
    my $zone_for_rootdomain = $zone_obj->get_zone_for_domain($rootdomain);

    if ( !$zone_for_rootdomain ) {
        die "“$rootdomain” has no zone in this DNS cluster!";
    }

    if ( $zone_for_rootdomain ne $rootdomain ) {

        if ( length($rootdomain) > length($zone_for_rootdomain) ) {

            # Example
            # $subdomain           = bob
            # $rootdomain          = my.happy.org
            # $zone_for_rootdomain = happy.org
            my $extra = $rootdomain =~ s/\.\Q$zone_for_rootdomain\E$//gr;
            $rootdomain = $zone_for_rootdomain;
            $subdomain .= '.' . $extra;
        }
        else {
            # Example
            # $subdomain           = bob.my
            # $rootdomain          = happy.org
            # $zone_for_rootdomain = my.happy.org
            my $remove = $zone_for_rootdomain =~ s/\.\Q$rootdomain\E$//gr;
            $rootdomain = $zone_for_rootdomain;
            $subdomain =~ s{\.\Q$remove\E$}{};
        }
    }
    return ( $subdomain, $rootdomain );
}

1;
