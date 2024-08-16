package Whostmgr::API::1::Session;

# cpanel - Whostmgr/API/1/Session.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception ();
use Cpanel::Locale::Lazy 'lh';
use Cpanel::Services::Ports ();
use Cpanel::Debug           ();

use constant NEEDS_ROLE => {
    create_user_session => undef,
};

use Try::Tiny;

my %PORTS = (
    'whostmgrd' => $Cpanel::Services::Ports::SERVICE{'whostmgrs'},
    'cpaneld'   => $Cpanel::Services::Ports::SERVICE{'cpanels'},
    'webmaild'  => $Cpanel::Services::Ports::SERVICE{'webmails'},
);

sub create_user_session ( $args, $metadata, @ ) {    ## no critic(Subroutines::ProhibitExcessComplexity)

    foreach my $param (qw(user service)) {
        if ( !exists $args->{$param} && !exists $args->{$param} ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = lh()->maketext( 'The “[_1]” parameter is required.', $param );
            return;
        }
    }

    my $user             = $args->{'user'};
    my $service          = $args->{'service'};
    my $session_locale   = $args->{'locale'};
    my $app              = $args->{'app'};
    my $preferred_domain = $args->{'preferred_domain'};

    if ( !$PORTS{$service} ) {
        $metadata->{'reason'} = lh()->maketext(
            "The “[_1]” parameter is invalid. The only supported [numerate,_2,service,services] for this API call [numerate,_2,is,are] [list_and_quoted,_3].",
            'service',
            ( scalar keys %PORTS ),
            [ sort keys %PORTS ]
        );
        $metadata->{'result'} = 0;
        return;
    }
    elsif ( !_account_exists($user) ) {
        $metadata->{'reason'} = lh()->maketext( "You cannot create a session for the user “[_1]” because they do not exist.", $user );
        $metadata->{'result'} = 0;
        return;
    }

    if ( $user ne 'root' ) {
        _verify_distributed_status_for_service( $user, $service );
    }

    require Cpanel::AcctUtils::Suspended;
    if ( Cpanel::AcctUtils::Suspended::is_suspended($user) ) {
        $metadata->{'reason'} = lh()->maketext( "You cannot create a session for the user “[_1]” because they are currently suspended.", $user );
        $metadata->{'result'} = 0;
        return;
    }

    require Whostmgr::AcctInfo::Owner;
    require Whostmgr::ACLS;
    if ( ( $user eq 'root' && $service ne 'whostmgrd' ) || ( !Whostmgr::ACLS::hasroot() && $ENV{'REMOTE_USER'} ne $user && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user ) ) ) {
        $metadata->{'reason'} = lh()->maketext( "You do not have permission to create sessions for the user “[_1]”.", $user );
        $metadata->{'result'} = 0;
        return;
    }
    elsif ( $session_locale && length($session_locale) > 16 ) {
        $metadata->{'reason'} = lh()->maketext( "The “[_1]” parameter is invalid. The “[_1]” parameter may not be longer than 16 characters.", $session_locale );
        $metadata->{'result'} = 0;
        return;

    }

    if ( $service eq 'whostmgrd' ) {
        require Cpanel::Reseller;
        if ( !Cpanel::Reseller::isreseller($user) ) {
            $metadata->{'reason'} = lh()->maketext( "You cannot create a “[_1]” session for the user “[_2]” because they are not a reseller.", 'whostmgrd', $user );
            $metadata->{'result'} = 0;
            return;
        }
    }

    if ($preferred_domain) {
        require Cpanel::Validate::Domain::Tiny;
        require Cpanel::Validate::IP;
        require Cpanel::Domain::Local;
        if ( !Cpanel::Validate::Domain::Tiny::validdomainname( $preferred_domain, 1 ) && !Cpanel::Validate::IP::is_valid_ip($preferred_domain) ) {
            $metadata->{'reason'} = lh()->maketext( "The “[_1]” parameter is invalid. The “[_1]” parameter must be a valid domain name or [asis,IP address].", $preferred_domain );
            $metadata->{'result'} = 0;
            return;
        }

        # https://en.wikipedia.org/wiki/Uniform_resource_locator
        # scheme://[user:password@]domain:port/path?query_string#fragment_id
        # domain name or literal numeric IP address
        elsif ( !Cpanel::Domain::Local::domain_or_ip_is_on_local_server($preferred_domain) ) {
            $metadata->{'reason'} = lh()->maketext( "The “[_1]” parameter is invalid. The “[_1]” parameter must be a domain or [asis,IP address] on this server.", $preferred_domain );
            $metadata->{'result'} = 0;
            return;
        }
    }

    #TODO: use validation in Cpanel::Theme::Assets::Link::attributes
    if ( length $app && $app !~ m/^[0-9a-z-_]+$/i ) {
        $metadata->{'reason'} = lh()->maketext( "The requested application, [_1], is invalid.", $app );
        $metadata->{'result'} = 0;
        return;
    }

    my $token = $args->{'cp_security_token'};
    require Cpanel::Session;
    if ( !$token || !Cpanel::Session::is_active_security_token_for_user( $user, $token ) ) {

        # Cannot reuse token
        $token = Cpanel::Session::generate_new_security_token();
    }

    my $ctime = time();

    my $session_obj = eval { Cpanel::Session->new(); };

    if ($@) {
        $metadata->{'reason'} = 'Could not create Cpanel::Session object: ' . $@;
        $metadata->{'result'} = 0;
        return;
    }

    my $randsession = $session_obj->create(
        'user'    => $user,
        'session' => {
            'user'                                    => $user,
            'successful_external_auth_with_timestamp' => time(),
            'cp_security_token'                       => $token,
            'service'                                 => $service,
            ( $session_locale ? ( 'session_locale' => $session_locale ) : () ),
            'tfa_verified' => 1,                                      # case CPANEL-5956: create_user_session should not require 2FA since its already authenticated
            'creator'      => ( $ENV{'REMOTE_USER'} || 'unknown' ),
            'origin'       => {
                'app'     => __PACKAGE__,
                'method'  => 'create_user_session',
                'creator' => ( $ENV{'REMOTE_USER'} || 'unknown' ),
                'address' => $ENV{'REMOTE_ADDR'}
            },
        },
        'tag' => 'create_user_session',
    );

    if ($randsession) {
        my $port = $PORTS{$service};
        my $host = $preferred_domain;
        if ( !$host ) {
            $host = $ENV{'HTTP_HOST'};

            local $SIG{__WARN__} = sub {
                $metadata->add_warning($_);
            };

            if ( !_hostname_confirmed_to_resolve_to_server() ) {

                # This is going to produce an SSL warning since the certificate
                # obviously won’t have the IP address; however, we also can’t
                # use the hostname because we can’t establish that DNS
                # resolves the hostname to the server (yet?).
                $host = _public_ip();
            }
            else {
                $host ||= _gethostname();
                require Cpanel::SSL::Domain;
                my ( $ssl_domain_info_status, $ssl_domain_info ) = Cpanel::SSL::Domain::get_best_ssldomain_for_object( $host, { 'service' => 'cpanel' } );
                if ( $ssl_domain_info_status && $ssl_domain_info->{'ssldomain'} ) {
                    $host = $ssl_domain_info->{'ssldomain'};
                }
            }
        }
        $metadata->{'reason'} = 'Created session';
        $metadata->{'result'} = 1;
        my $url              = "https://$host:$port$token/login/";
        my %url_query_params = ( 'session' => $randsession );
        if ($app) {
            if ( $service eq 'cpaneld' ) {
                require Cpanel::Themes;
                my $app_url = Cpanel::Themes::get_users_links($user);
                $url_query_params{'goto_uri'} = $app_url->{$app}
                  if $app_url->{$app};
            }
            elsif ( $service eq 'whostmgrd' ) {
                require Whostmgr::DynamicUI::Loader;
                my $dynamicui_items = Whostmgr::DynamicUI::Loader::load_dynamicui_conf( '/usr/local/cpanel/whostmgr/docroot/themes/x/dynamicui.conf', 1 );
                foreach my $item ( @{$dynamicui_items} ) {
                    next if !( exists $item->{'key'} && $item->{'key'} eq $app && $item->{'url'} );

                    if ( Whostmgr::DynamicUI::Loader::check_flags( $item, $user ) ) {
                        $url_query_params{'goto_uri'} = $item->{'url'};
                    }
                    last;    # stop looping after we find a match for the app once
                }
            }
        }
        if ( length $session_locale ) {
            $url_query_params{'locale'} = $session_locale;
        }
        require Cpanel::HTTP::QueryString;
        $url .= '?' . Cpanel::HTTP::QueryString::make_query_string( \%url_query_params );

        require Cpanel::Config::Session;
        return {
            'cp_security_token' => $token,
            ( $session_locale ? ( 'locale' => $session_locale ) : () ),
            'expires' => ( $ctime + $Cpanel::Config::Session::PREAUTH_SESSION_DURATION ),
            'service' => $service,
            'session' => $randsession,
            'url'     => $url,
        };
    }
    else {
        $metadata->{'reason'} = 'Failed to create session';
        $metadata->{'result'} = 0;
        return;
    }
}

sub _verify_distributed_status_for_service ( $username, $service_name ) {

    require Cpanel::Config::LoadCpUserFile;

    my $err;

    if ( $service_name eq 'webmaild' ) {
        my $cpuser_obj = Cpanel::Config::LoadCpUserFile::load_if_exists($username);

        if ($cpuser_obj) {
            require Cpanel::LinkedNode::Worker::GetAll;
            if ( my $mail_hr = Cpanel::LinkedNode::Worker::GetAll::get_one_from_cpuser( 'Mail', $cpuser_obj ) ) {
                $err = lh()->maketext( "Send this request to “[_1]”, not this server.", $mail_hr->{'configuration'}->hostname() );
            }
        }
    }
    else {
        my $cpuser_obj = Cpanel::Config::LoadCpUserFile::load($username);

        if ( $cpuser_obj->child_workloads() ) {
            $err = lh()->maketext("Send this request to this account’s parent node, not this server.");
        }
    }

    die "$err\n" if $err;

    return;
}

sub _gethostname {
    require Cpanel::Hostname;
    return Cpanel::Hostname::gethostname();
}

sub _account_exists {
    my ($user) = @_;

    require Cpanel::AcctUtils::Lookup;
    my ( $sysuser, $err );
    try {
        $sysuser = Cpanel::AcctUtils::Lookup::get_system_user($user);
    }
    catch {
        $err = $_;
    };

    return 0 if $err;

    require Cpanel::AcctUtils::Account;
    return Cpanel::AcctUtils::Account::accountexists($sysuser) ? 1 : 0;
}

sub _hostname_resolves_to_server {
    require Cpanel::Hostname::Resolution;
    return Cpanel::Hostname::Resolution->load();
}

sub _hostname_confirmed_to_resolve_to_server {
    my $resolves_yn;

    try {
        $resolves_yn = _hostname_resolves_to_server();
    }
    catch {
        my $hostname = _gethostname();
        my $errstr   = Cpanel::Exception::get_string($_);

        warn "Failed to determine if this system’s hostname ($hostname) resolves locally; assuming no: $errstr\n";
    };

    return $resolves_yn;
}

sub _public_ip {
    require Cpanel::DIp::MainIP;
    require Cpanel::NAT;
    return Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainip() );
}

1;
