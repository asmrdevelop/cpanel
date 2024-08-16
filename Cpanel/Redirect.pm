package Cpanel::Redirect;

# cpanel - Cpanel/Redirect.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Hostname                    ();
use Cpanel::Ident                       ();
use Cpanel::Config::LoadCpConf          ();
use Cpanel::Rand::Get                   ();
use Cpanel::SSL::Domain                 ();
use Cpanel::Services::Ports             ();
use Cpanel::Server::Type::Role::Webmail ();
use Cpanel::JSON                        ();
use Cpanel::Encoder::URI                ();

my $HTTPS_PORT = 443;

our $VERSION = '1.7';

my $portmap_ref = {
    'webmail' => {
        'ssl' => $Cpanel::Services::Ports::SERVICE{'webmails'},
        ''    => $Cpanel::Services::Ports::SERVICE{'webmail'},
    },
    'whm' => {
        'ssl' => $Cpanel::Services::Ports::SERVICE{'whostmgrs'},
        ''    => $Cpanel::Services::Ports::SERVICE{'whostmgr'},
    },
    'cpanel' => {
        'ssl' => $Cpanel::Services::Ports::SERVICE{'cpanels'},
        ''    => $Cpanel::Services::Ports::SERVICE{'cpanel'},
    },
};

sub determine_redirect_host_non_ssl {
    my ($given_host) = @_;

    return _determine_redirect_data( 0, $given_host )->{'redirect_target_host'};
}

sub determine_redirect_host_ssl {
    my ($given_host) = @_;

    return _determine_redirect_data( 1, $given_host )->{'redirect_target_host'};
}

# Refactored … could definitely be made cleaner.
sub _determine_redirect_data {
    my ( $ssl_yn, $redirect_target_host, $cpconf_ref ) = @_;

    # The result of this function is a result of the following:
    #
    # whether the connection is SSL
    # alwaysredireecttossl
    # cpredirect
    # cpredirectssl
    # cpredirecthostname

    $cpconf_ref ||= Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    my ( $ssl_domain_info_status, $ssl_domain_info );

    if ( _should_redirect_to_hostname( $ssl_yn, $cpconf_ref ) ) {    # this always returns false if alwaysredirecttossl=0
        $redirect_target_host = Cpanel::Hostname::gethostname();
    }
    else {
        if ( _should_redirect_ssl_host( $ssl_yn, $cpconf_ref ) ) {    # this always returns true if alwaysredirecttossl=1
            my ( $ssl_domain_info_status, $ssl_domain_info ) = Cpanel::SSL::Domain::get_best_ssldomain_for_object( $redirect_target_host || Cpanel::Hostname::gethostname(), { 'service' => 'cpanel' } );
            if ( $ssl_domain_info_status && $ssl_domain_info->{'ssldomain'} ) {
                $redirect_target_host = $ssl_domain_info->{'ssldomain'};
            }
        }

        if ( !$redirect_target_host ) {
            $redirect_target_host = Cpanel::Hostname::gethostname();
        }
    }

    return {
        redirect_target_host   => $redirect_target_host,
        ssl_domain_info_status => $ssl_domain_info_status,
        ssl_domain_info        => $ssl_domain_info,
    };
}

sub redirect {
    my %OPTS       = @_;
    my $ssl        = $OPTS{'ssl'} || 0;
    my $service    = $OPTS{'service'};
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();

    if ( ( !$ssl && $ENV{'HTTPS'} && $ENV{'HTTPS'} eq 'on' ) || $cpconf_ref->{'alwaysredirecttossl'} || _connection_is_using_ssl() ) { $ssl = 1; }

    if ( !-r '/var/cpanel/ssl' ) {
        print STDERR "Warning: /var/cpanel/ssl is not accessible, redirection will likely be broken.\n";
    }
    elsif ( !-r '/var/cpanel/ssl/cpanel' ) {
        print STDERR "Warning: /var/cpanel/ssl/cpanel is not accessible, redirection will likely be broken.\n";
    }

    my $redir_hr = _determine_redirect_data( !!$ssl, $ENV{'HTTP_HOST'}, $cpconf_ref );

    my ( $redirect_target_host, $ssl_domain_info_status, $ssl_domain_info ) = @{$redir_hr}{
        qw(
          redirect_target_host
          ssl_domain_info_status
          ssl_domain_info
        )
    };

    # If Mail is disabled and they ask for /webmail we sent them to cPanel
    # because there isn't much else we can do
    if ( index( $service, 'webmail' ) > -1 && !Cpanel::Server::Type::Role::Webmail->is_enabled() ) {
        $service = 'cpanel';
    }

    my $port           = $portmap_ref->{$service}->{ ( $ssl ? 'ssl' : '' ) };
    my $nonsecure_port = $portmap_ref->{$service}->{''};

    my $redirecturl           = 'http' . ( $ssl ? 's' : '' ) . '://' . $redirect_target_host . ':' . $port;
    my $nonsecure_redirecturl = 'http://' . $redirect_target_host . ':' . $nonsecure_port;
    my $proxyurl;
    my $nonsecure_proxyurl;

    my $proxyssl = 0;
    if ( $cpconf_ref->{'proxysubdomains'} ) {
        my $user = ( getpwuid($>) )[0];
        if ($user) {
            require Cpanel::AcctUtils::Domain;
            if ( my $maindomain = Cpanel::AcctUtils::Domain::getdomain($user) ) {
                local $ENV{'PATH'} = '/bin:/usr/bin';    # Required to pass taint checking
                $proxyssl = $ssl;

                # We always have a default ssl vhost now
                $proxyurl           = 'http' . ( $proxyssl ? 's' : '' ) . '://' . $service . '.' . $maindomain;
                $nonsecure_proxyurl = 'http://' . $service . '.' . $maindomain;
            }
        }
    }

    if ( $proxyurl && !defined $ssl_domain_info_status ) {
        ( $ssl_domain_info_status, $ssl_domain_info ) = Cpanel::SSL::Domain::get_best_ssldomain_for_object( $redirect_target_host || Cpanel::Hostname::gethostname(), { 'service' => 'cpanel' } );
    }

    # We previously checked to see if cpsrvd had a signed certificate
    # we also need to know of the ssl_domain we are redirecting to is part
    # of the signed certificate.  This now uses a safer more robust check
    # that only set the domain as 'signed' if it is matching the cert
    if ( $proxyurl && $ssl_domain_info_status && !$ssl_domain_info->{'is_self_signed'} ) {
        require Cpanel::Encoder::Tiny;
        print "Content-type: text/html\r\n\r\n";

        my $ishttps              = ( $ssl ? 1 : 0 );
        my $uri_encoded_goto_uri = _request_uri_as_param();
        require Cpanel::WebTemplates;
        require Cpanel::AcctUtils::SiteOwner;
        my ( $user, $owner ) = Cpanel::AcctUtils::SiteOwner::get_site_owner( $ENV{'HTTP_HOST'} );
        if ( !$user && $ENV{'SERVER_NAME'} eq Cpanel::Hostname::gethostname() ) {
            $user  = 'nobody';
            $owner = 'root';
        }
        my $random = Cpanel::Rand::Get::getranddata(16);

        my ( $status, $output ) = Cpanel::WebTemplates::process_web_template(
            'redirect',
            'english',
            $owner,
            {
                'data' => {

                    # Legacy templates
                    'js_safe_redirecturl'           => _js_safe( Cpanel::Encoder::Tiny::safe_html_encode_str($redirecturl) ),
                    'js_safe_proxyurl'              => _js_safe( Cpanel::Encoder::Tiny::safe_html_encode_str($proxyurl) ),
                    'js_safe_nonsecure_redirecturl' => _js_safe( Cpanel::Encoder::Tiny::safe_html_encode_str($nonsecure_redirecturl) ),
                    'js_safe_nonsecure_proxyurl'    => _js_safe( Cpanel::Encoder::Tiny::safe_html_encode_str($nonsecure_proxyurl) ),

                    # Newer templates
                    'json_preferredMethod_test_url'      => Cpanel::JSON::SafeDump("$redirecturl/unprotected/loader.html?random=$random&goto_uri=$uri_encoded_goto_uri"),
                    'json_proxyMethod_test_url'          => Cpanel::JSON::SafeDump("$proxyurl/unprotected/loader.html?random=$random&goto_uri=$uri_encoded_goto_uri"),
                    'json_nonsecureMethod_test_url'      => Cpanel::JSON::SafeDump("$nonsecure_redirecturl/unprotected/loader.html?random=$random&goto_uri=$uri_encoded_goto_uri"),
                    'json_nonsecureProxyMethod_test_url' => Cpanel::JSON::SafeDump("$nonsecure_proxyurl/unprotected/loader.html?random=$random&goto_uri=$uri_encoded_goto_uri"),

                    'preferredMethod_test_url'      => "$redirecturl/unprotected/loader.html?random=$random&goto_uri=$uri_encoded_goto_uri",
                    'proxyMethod_test_url'          => "$proxyurl/unprotected/loader.html?random=$random&goto_uri=$uri_encoded_goto_uri",
                    'nonsecureMethod_test_url'      => "$nonsecure_redirecturl/unprotected/loader.html?random=$random&goto_uri=$uri_encoded_goto_uri",
                    'nonsecureProxyMethod_test_url' => "$nonsecure_proxyurl/unprotected/loader.html?random=$random&goto_uri=$uri_encoded_goto_uri",

                    'json_preferredMethod_redirect_url'      => Cpanel::JSON::SafeDump( _append_request_uri_after_first_path($redirecturl) ),
                    'json_proxyMethod_redirect_url'          => Cpanel::JSON::SafeDump( _append_request_uri_after_first_path($proxyurl) ),
                    'json_nonsecureMethod_redirect_url'      => Cpanel::JSON::SafeDump( _append_request_uri_after_first_path($nonsecure_redirecturl) ),
                    'json_nonsecureProxyMethod_redirect_url' => Cpanel::JSON::SafeDump( _append_request_uri_after_first_path($nonsecure_proxyurl) ),

                    'preferredMethod_redirect_url'      => _append_request_uri_after_first_path($redirecturl),
                    'proxyMethod_redirect_url'          => _append_request_uri_after_first_path($proxyurl),
                    'nonsecureMethod_redirect_url'      => _append_request_uri_after_first_path($nonsecure_redirecturl),
                    'nonsecureProxyMethod_redirect_url' => _append_request_uri_after_first_path($nonsecure_proxyurl),

                    # All templates
                    'port'          => $port,
                    'preview'       => 0,
                    'ishttps'       => $ishttps,
                    'proxy_ishttps' => $proxyssl,
                    'random'        => $random,
                    'protocol'      => ( $ENV{'HTTPS'} ? 'https' : 'http' )
                }
            }
        );
    }
    else {
        my $headers = 'Status: 301' . "\r\n";
        $headers .= 'Location: ' . _append_request_uri_after_first_path($redirecturl) . "\r\n";
        $headers .= "\r\n";
        print $headers;    # minimize the number of packets sent
    }
    return;
}

sub getserviceSSLdomain {
    my ( $service, $domain ) = @_;

    $domain  ||= Cpanel::Hostname::gethostname();
    $service ||= 'cpanel';

    my ( $ok, $ssl_domain_info ) = Cpanel::SSL::Domain::get_best_ssldomain_for_object( $domain, { 'service' => $service } );

    return $ssl_domain_info->{'ssldomain'};
}

sub cpsrvd_has_signed_cert {
    if ( !-e '/var/cpanel/ssl/cpanel/mycpanel.pem' ) {
        return 0;
    }

    my ( $ok, $service_cert_info ) = Cpanel::SSL::Domain::load_service_certificate_info('cpanel');

    return 0 if !$ok;

    my $is_self_signed = $service_cert_info->{'is_self_signed'};

    return 0 if ($is_self_signed);
    return 1;
}

sub _should_redirect_to_hostname {
    my ( $ssl, $cpconf_ref ) = @_;

    return 0 if $cpconf_ref->{'alwaysredirecttossl'};

    my $cpconf_redirect_key = 'cpredirect' . ( $ssl ? 'ssl' : '' );

    if (   ( !defined $cpconf_ref->{$cpconf_redirect_key} && $cpconf_ref->{'cpredirecthostname'} )
        || ( $cpconf_ref->{$cpconf_redirect_key} && $cpconf_ref->{$cpconf_redirect_key} =~ /hostname/i ) ) {
        return 1;
    }

    return 0;
}

sub _should_redirect_ssl_host {
    my ( $ssl, $cpconf_ref ) = @_;

    return 1 if $cpconf_ref->{'alwaysredirecttossl'};

    if ( $ssl && ( !defined $cpconf_ref->{'cpredirectssl'} || $cpconf_ref->{'cpredirectssl'} =~ /ssl/i ) ) {
        return 1;
    }
    return 0;
}

#We can’t just check $ENV{'HTTPS'} here because service (formerly proxy) subdomains
#connect to port 2082 in cPanel.
#NOTE: Overridden in tests.
sub _connection_is_using_ssl {
    return 1 if $ENV{'HTTPS'};         # if it is set we can at least avoid the netlink call
    my ( $remote_addr, $remote_port, $server_addr ) = @ENV{qw(REMOTE_ADDR REMOTE_PORT SERVER_ADDR)};
    local $SIG{__WARN__} = sub { };    # suppress Netlink warnings (CPANEL-6011)
    return defined( Cpanel::Ident::identify_local_connection( $remote_addr, $remote_port, $server_addr, $HTTPS_PORT ) );
}

sub _request_uri_as_param {
    my $request_uri = $ENV{'REQUEST_URI'};

    # If there is anothering after the first path append it to the
    # url we will redirect them to ex
    # /webmail/(THIS)
    # /cpanel/(THIS)
    # /whm/(THIS)
    if ( $request_uri =~ m{^/[^/]+/(.*)} ) {
        return Cpanel::Encoder::URI::uri_encode_str( '/' . $1 );
    }
    return '';
}

sub _append_request_uri_after_first_path {
    my ($original_uri) = @_;

    my $request_uri = $ENV{'REQUEST_URI'};

    # If there is anothering after the first path append it to the
    # url we will redirect them to ex
    # /webmail/(THIS)
    # /cpanel/(THIS)
    # /whm/(THIS)
    if ( $request_uri =~ m{^/[^/]+/(.*)} ) {
        $original_uri .= '/' if $original_uri !~ m{/$};
        $original_uri .= $1;                              # Already encoded
    }
    return $original_uri;
}

sub _js_safe {
    my ($text) = @_;

    $text =~ s/\'/\\\'/g;
    $text =~ s/\"/\\\"/g;

    return $text;
}
1;
