package Cpanel::DnsUtils::Add;

# cpanel - Cpanel/DnsUtils/Add.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Imports;

use Cpanel::AcctUtils::DomainOwner       ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Config::LoadWwwAcctConf      ();
use Cpanel::Config::ModCpUserFile        ();
use Cpanel::Debug                        ();
use Cpanel::DnsUtils::Exists             ();
use Cpanel::DnsUtils::AskDnsAdmin        ();
use Cpanel::DnsUtils::Stream             ();
use Cpanel::DnsUtils::Template           ();
use Cpanel::IPv6::Normalize              ();
use Cpanel::FileUtils::Lines             ();
use Cpanel::Hostname                     ();
use Cpanel::LoadModule                   ();
use Cpanel::NameserverCfg                ();
use Cpanel::PwCache                      ();
use Cpanel::Validate::Domain             ();
use Cpanel::Validate::IP                 ();
use Cpanel::Validate::IP::v4             ();
use Whostmgr::Func                       ();
use Whostmgr::Transfers::State           ();

################################################################
# doadddns - Add a dns entry by whatever method is configured
#  Params:
#     domain  -       The domain for the dns entry
#     ip      -       The ip for the dns entry
#     reseller-       Used to configure the nameservers
#     allowoverwrite- Overwrite existing zones
#     trueowner -     The user who will own the domain
#     ownerok   -     Set this if the owner has been validated
#     nodnsreload-    Reload Bind/NSD/ETC after adding the zone (deprecated)
#     template    -   Template to use: defaults to standard
#

# The installer checks for STATUS_NO_NSS_CONFD and suppresses
# the error if it is found as its an expected condition.

use constant {
    STATUS_NO_NSS_CONFD => 10,
};

sub doadddns {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my %OPTS           = @_;
    my $domain         = $OPTS{'domain'};
    my $ip             = $OPTS{'ip'};
    my $reseller       = $OPTS{'reseller'} || '';    # warning if left undef
    my $allowoverwrite = $OPTS{'allowoverwrite'};
    my $trueowner      = $OPTS{'trueowner'};
    my $nodnsreload    = $OPTS{'nodnsreload'};       # Ignored with new DNS system
    my $is_restore     = $OPTS{'is_restore'};
    my $template       = $OPTS{'template'};
    my $has_ipv6       = $OPTS{'has_ipv6'};
    my $ipv6           = $OPTS{'ipv6'};

    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    #
    # Cpanel::NameserverCfg::fetch is used now to fetch nameservers so no need to check them here
    #
    my $use_authoritative_nameservers = $cpconf_ref->{'useauthnameservers'} || 0;
    my $autocreateaentries            = $cpconf_ref->{'autocreateaentries'} // 0;

    require Cpanel::Validate::Domain::Normalize;

    my $hostname = Cpanel::Hostname::gethostname();
    $domain = Cpanel::Validate::Domain::Normalize::normalize($domain);

    if ( !$domain ) {
        return ( 0, "Sorry, you must enter a domain.  Please try again." );
    }

    if ( !$ip ) {
        return ( 0, "Sorry, you must enter an ip.  Please try again." );
    }

    if ( ( defined $template ) && ( $template =~ /\n/ ) ) {
        return ( 0, "Sorry, template names cannot contain a newline.  Please try again." );
    }

    if (  !Cpanel::Validate::Domain::is_valid_cpanel_domain($domain)
        || Cpanel::Validate::IP::v4::is_valid_ipv4($domain) ) {
        return ( 0, "Sorry, that's an invalid domain\n" );
    }

    {
        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();
        if ( !Whostmgr::ACLS::hasroot() ) {
            require Cpanel::Validate::Component::Domain::IsPublicSuffix;
            require Cpanel::OrDie;
            my $public_suffix_component = Cpanel::Validate::Component::Domain::IsPublicSuffix->new( 'domain' => $domain );

            my ( $status, $msg ) = Cpanel::OrDie::convert_die_to_multi_return( sub { $public_suffix_component->validate() } );

            return ( $status, $msg ) if !$status;
        }
    }

    my $skip_userdomains_addition = 0;
    if ( $domain eq Cpanel::Validate::Domain::Normalize::normalize($hostname) ) {
        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();
        if ( !Whostmgr::ACLS::hasroot() ) {
            return ( 0, "Sorry, you can not add a DNS record for the system hostname." );
        }
        $skip_userdomains_addition = 1;
    }

    if ( !$cpconf_ref->{'allowresellershostnamedomainsubdomains'} ) {
        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();
        if ( !Whostmgr::ACLS::hasroot() && Whostmgr::Func::is_true_subdomain_of_domain( $domain, $hostname ) ) {
            return ( 0, 'Sorry, you can not add a DNS record a subdomain of the server’s hostname.' );
        }
    }

    if ( !$cpconf_ref->{'allowwhmparkonothers'} ) {
        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();
        if ( !Whostmgr::ACLS::hasroot() ) {
            my ( $user_can_own, $owned_domain, $owning_user ) = Cpanel::AcctUtils::DomainOwner::check_each_domain_level_for_ownership( $ENV{'REMOTE_USER'} || $trueowner, $domain );
            if ( !$user_can_own ) {
                return ( 0, 'Sorry, you can not add a DNS record for a subdomain of another user’s domain.' );
            }
        }
    }

    if ( $cpconf_ref->{'blockcommondomains'} ) {
        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();
        if ( !Whostmgr::ACLS::hasroot() ) {
            require Cpanel::Validate::Component::Domain::IsCommon;
            require Cpanel::OrDie;
            my $common_domain_component = Cpanel::Validate::Component::Domain::IsCommon->new( 'domain' => $domain, 'blockcommondomains' => 1 );

            my ( $status, $msg ) = Cpanel::OrDie::convert_die_to_multi_return( sub { $common_domain_component->validate() } );

            return ( $status, $msg ) if !$status;
        }
    }

    if ( my $msg = _get_ddns_conflict_msg($domain) ) {
        return ( 0, $msg );
    }

    if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($ip) ) {
        return ( 0, "Sorry, the IP address appears to be invalid." );
    }

    # n/a needed due to it's use as a placeholder for "null"
    if ( defined($ipv6) && $ipv6 ne Cpanel::IPv6::Normalize::DOES_NOT_HAVE_IPV6_STRING() && !Cpanel::Validate::IP::is_valid_ipv6($ipv6) ) {
        return ( 0, "Sorry, that ($ipv6) appears to be an invalid IPv6 address." );
    }

    $trueowner = 'system' if length $trueowner && $trueowner eq 'root';

    if ( !$is_restore && $trueowner ) {
        my $current_owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { default => '', 'skiptruelookup' => 1 } );
        if ($current_owner) {
            if ( $current_owner ne $trueowner ) {
                return ( 0, "Sorry, the domain $domain is owned by another user ($current_owner)" );
            }
            $skip_userdomains_addition = 1;
        }
    }

    my $wwconf_ref   = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    my $contactemail = $wwconf_ref->{'CONTACTEMAIL'};
    my $ttl          = $wwconf_ref->{'TTL'};
    my $nsttl        = $wwconf_ref->{'NSTTL'};
    if ( !$contactemail ) {
        $contactemail = 'root@' . $hostname;
    }

    my $rpemail = $contactemail;
    $rpemail =~ s/\,.*$//g;
    $rpemail =~ s/\;.*$//g;
    $rpemail =~ tr/ \r\n\t//d;
    $rpemail =~ tr/@/./;

    $reseller =~ tr/ \r\n\t//d;

    if ( !$reseller ) { $reseller = $ENV{'REMOTE_USER'}; }

    my ( $nameserver, $nameserver2, $nameserver3, $nameserver4 ) = Cpanel::NameserverCfg::fetch($reseller);
    for ( $nameserver, $nameserver2, $nameserver3, $nameserver4 ) { $_ ||= '' }    # default to empty string if not specified

    unless ( $nameserver || $nameserver2 || $nameserver3 || $nameserver4 ) {

        # The initial dns zone on fresh installs was failing until we added this fallback
        Cpanel::Debug::log_info("This system does not have any configured nameservers. The system will use the authoritative nameservers for the domain “$domain”.");
        $use_authoritative_nameservers = 1;
    }

    if ( !$allowoverwrite ) {
        if ( Cpanel::DnsUtils::Exists::domainexists($domain) ) {
            return ( 0, "Sorry, a DNS entry for $domain already exists\n" );
        }
    }

    my $sr = Cpanel::DnsUtils::Stream::getnewsrnum(0);

    # Ensure nameserver ttl and zone ttl are set properly
    if ( !defined $ttl || $ttl eq '' || $ttl !~ m{ \A \d+ \z }xms ) {
        $ttl = '14400';
    }
    if ( !defined $nsttl || $nsttl eq '' || $nsttl !~ m{ \A \d+ \z }xms ) {
        $nsttl = '86400';
    }

    my ( $nameservera,     $nameservera2,     $nameservera3,     $nameservera4 );
    my ( $nameserverentry, $nameserverentry2, $nameserverentry3, $nameserverentry4 );
    if ( $use_authoritative_nameservers || $autocreateaentries ) {

        require Cpanel::DnsRoots;

        # fetchnameservers is called directly not from the object
        my ( $result, undef, $names ) = Cpanel::DnsRoots::fetchnameservers($domain);

        if ($result) {
            my %NAMES = %$names;

            my @nameservers      = sort keys %NAMES;
            my @namserverentries = grep { m/\.\Q${domain}\E$/i } @nameservers;
            my @nameserveras     = map  { $NAMES{$_} } @namserverentries;

            for my $i ( 0 .. 3 ) {
                $nameservers[$i] ||= '';
            }

            if ( ( scalar keys %NAMES ) > 0 && $use_authoritative_nameservers ) {
                ( $nameserver, $nameserver2, $nameserver3, $nameserver4 ) = @nameservers;
            }

            if ($autocreateaentries) {
                ( $nameserverentry, $nameserverentry2, $nameserverentry3, $nameserverentry4 ) = @namserverentries;
                ( $nameservera,     $nameservera2,     $nameservera3,     $nameservera4 )     = @nameserveras;
            }
        }
        else {
            local $Cpanel::Logger::ENABLE_BACKTRACE = 0;
            Cpanel::Debug::log_warn("The system failed to fetch the authoritative nameservers for the domain “$domain”.");
        }
    }

    unless ( $nameserver || $nameserver2 || $nameserver3 || $nameserver4 ) {
        return ( 0, "Sorry, you cannot create zones if you have not configured at least one nameserver.", STATUS_NO_NSS_CONFD );
    }

    my ( $nameddata, $error ) = Cpanel::DnsUtils::Template::getzonetemplate(
        ( $template ? $template : 'standard' ),
        $domain,
        {
            'domain'      => $domain,
            'ip'          => $ip,
            'ftpip'       => $ip,
            'reseller'    => $reseller,
            'rpemail'     => $rpemail,
            'nameserver'  => $nameserver,
            'nameserver2' => $nameserver2,
            'nameserver3' => $nameserver3,
            'nameserver4' => $nameserver4,

            'nameservera'  => $nameservera,
            'nameservera2' => $nameservera2,
            'nameservera3' => $nameservera3,
            'nameservera4' => $nameservera4,

            'nameserverentry'  => $nameserverentry,
            'nameserverentry2' => $nameserverentry2,
            'nameserverentry3' => $nameserverentry3,
            'nameserverentry4' => $nameserverentry4,

            'serial' => $sr,
            'ttl'    => $ttl,
            'nsttl'  => $nsttl,

            'ipv6' => $has_ipv6 ? $ipv6 : undef,
        }
    );
    if ( !$nameddata ) {
        return ( 0, 'Sorry, An error occurred while generating the zone file.' );
    }

    # Account Restorations do local only because a DNS cluster sync
    # happens at the end of the restoration.
    my $_dns_local = Whostmgr::Transfers::State::is_transfer() ? $Cpanel::DnsUtils::AskDnsAdmin::LOCAL_ONLY : $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL;
    my $output     = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'QUICKZONEADD', $_dns_local, $domain, $nameddata );

    # check return message for failure
    if ( $output !~ m/Zone [^\s]+ has been successfully added/mi ) {

        # Cannot anchor this check because we may have a message able a deferred restart in this string
        return ( 0, 'Sorry, An error occurred while adding dns zone: ' . $output );
    }

### all these checks should be outside this function
    if ( $trueowner && !$skip_userdomains_addition ) {    #$skip_userdomains_addition can only happen if $allowoverwrite is true
                                                          # otherwise the if !$allowoverwrite block above will have already returned
                                                          # Sorry, a DNS entry for $domain already exists
        unless ($is_restore) {
            Cpanel::Config::ModCpUserFile::adddomaintouser( 'user' => $trueowner, 'domain' => $domain, 'type' => '' );
        }
        if ( $trueowner ne 'system' ) {
            my $uid = Cpanel::PwCache::getpwnam_noshadow($trueowner);

            if ($uid) {
                Cpanel::LoadModule::load_perl_module('Cpanel::Email::Perms::System');
                Cpanel::Email::Perms::System::ensure_domain_system_perms(
                    $uid,
                    $domain,
                );
            }
            else {
                warn "No UID found for user “$trueowner”!";
            }
        }

        # We must always add to /etc/userdomains even on a restore since
        # Cpanel::Domain::Zone needs this entry for subdomain on top of
        # subdomains.  This will get blown away the next time we run
        # updateuserdomains and that is OK
        Cpanel::FileUtils::Lines::appendline( "/etc/userdomains", "$domain: $trueowner" );

        return ( 1, "Added $domain ok belonging to user $trueowner" );
    }

    return ( 1, "Added $domain ok" );

}

sub _get_ddns_conflict_msg ($domain) {
    require Cpanel::PromiseUtils;
    require Cpanel::DynamicDNS::DomainsCache;
    require Cpanel::DnsUtils::Name;

    my $domain_id_hr = Cpanel::PromiseUtils::wait_anyevent(
        Cpanel::DynamicDNS::DomainsCache::read_p( timeout => 30 ),
    )->get();

    if ( $domain_id_hr->{$domain} ) {
        return ( 0, locale()->maketext( '“[_1]” is already a dynamic [asis,DNS] domain.', $domain ) );
    }

    my @conflicts;
    for my $ddns_domain ( sort keys %$domain_id_hr ) {
        if ( Cpanel::DnsUtils::Name::is_subdomain_of( $ddns_domain, $domain ) ) {
            push @conflicts, $ddns_domain;
        }
    }

    my $msg;
    if (@conflicts) {
        $msg = locale()->maketext( '[list_and_quoted,_1] [numerate,_2,is already a,are already] dynamic [asis,DNS] [numerate,_2,domain,domains]. Because [numerate,_2,this domain is a subdomain,these domains are subdomains] of “[_3]”, you cannot create a [asis,DNS] zone with that name.', \@conflicts, 0 + @conflicts, $domain );
    }

    return $msg;
}

1;
