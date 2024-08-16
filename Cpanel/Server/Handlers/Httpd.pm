package Cpanel::Server::Handlers::Httpd;

# cpanel - Cpanel/Server/Handlers/Httpd.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::Httpd - Bare-bones HTTP server

=head1 SYNOPSIS

    #This is how this class is normally instantiated.
    my $handler_obj = $server_obj->get_handler('Httpd');

    $handler_obj->handler();

=head1 DESCRIPTION

This module implements a tiny HTTP server in cpsrvd that executes a
whitelist of functionality.

This is useful for contexts where no other service is running on the standard
HTTP and HTTPS ports.

It implements the following behaviors:

=over

=item * Any request whose path is under F</.well-known> is served as a
static file. The path on disk that’s loaded is the same as under Apache.

=item * Any other request whose C<Host> header starts with one of the
following is served as appropriate: C<cpcalendars.>, C<cpcontacts.>,
C<autodiscover.>, C<autoconfig.>. The latter two are only served if
they are enabled in the server configuration.

Note that C<cpanel.>, C<whm.>, and C<webmail.> are NOT handled here.
This is largely because the relevant applications are under base cpsrvd
and thus not (readily) callable from this module, so we have to handle
those applications separately.

=back

This module subclasses L<Cpanel::Server::Handler>.

=cut

use parent 'Cpanel::Server::Handler';

use Cpanel::Exception                       ();
use Cpanel::LoadModule                      ();
use Cpanel::Server::Handlers::Httpd::Check  ();
use Cpanel::Server::Handlers::Httpd::Errors ();
use Cpanel::Server::Type                    ();

use constant {
    _STATIC_FILE_SIZE_SERVE_THRESHOLD => 32_768,
};

my %_HOST_ROUTE = (
    cpcalendars => 'proxy_cpcalendars_cpcontacts',
    cpcontacts  => 'proxy_cpcalendars_cpcontacts',

    autodiscover => 'autodiscover',
    autoconfig   => 'autoconfig',
);

our $_CPCALENDAR_CPCONTACTS_LOOPBACK_PORT = 2079;

our $_IMG_SYS_DIR    = '/usr/local/cpanel/img-sys';
our $_SYS_CPANEL_DIR = '/usr/local/cpanel/sys_cpanel';

=head1 INSTANCE METHODS

=head2 I<OBJ->handler()

Implement this module’s handling of the relevant connection.

=cut

sub handler {
    my ($self) = @_;

    my $http_host = $self->_get_and_validate_host_header();

    my $doc_path = $self->_get_and_validate_document_relpath();

    if ( Cpanel::Server::Handlers::Httpd::Check::is_valid_static_path($doc_path) ) {
        $self->_serve_static( $http_host, $doc_path );
    }

    elsif ( _is_mailman($doc_path) ) {
        require Cpanel::Server::Type::Profile::Roles;
        if ( !Cpanel::Server::Type::Profile::Roles::are_roles_enabled( { match => 'all', roles => [ 'MailReceive', 'MailSend' ] } ) || Cpanel::Server::Type::is_dnsonly() ) {
            _die_404();
        }

        require Cpanel::Server::Handlers::Httpd::Mailman;
        Cpanel::Server::Handlers::Httpd::Mailman::handle( $self->get_server_obj(), $http_host, $doc_path );
    }

    # Mailman needs this. We handle it here, though, rather than in Mailman.pm
    # because there could be something else that wants it, too.
    #
    # We don’t serve this from _serve_static() because _serve_static() imposes
    # a limit on the size of the response.
    elsif ( 0 == index( $doc_path, '/img-sys/' ) ) {

        # First 9 characters are “/img-sys/”.
        _serve_cp_app_static(
            $self->get_server_obj(),
            $http_host,
            $_IMG_SYS_DIR,
            substr( $doc_path, 9 ),
        );
    }

    # No need to serve BoxTrapper on DNS-only
    elsif ( $doc_path eq '/cgi-sys/bxd.cgi' && !Cpanel::Server::Type::is_dnsonly() ) {
        require Cpanel::Server::Handlers::Httpd::BoxTrapper;

        Cpanel::Server::Handlers::Httpd::BoxTrapper::handle_bxd(
            $self->get_server_obj(),
            _determine_setuid_user_by_host($http_host),
        );
    }

    # BoxTrapper needs this.
    elsif ( 0 == index( $doc_path, '/sys_cpanel/' ) ) {

        # First 12 characters are “/sys_cpanel/”.
        _serve_cp_app_static(
            $self->get_server_obj(),
            $http_host,
            $_SYS_CPANEL_DIR,
            substr( $doc_path, 12 ),
        );
    }

    # /cpanel, /whm, and /webmail redirection
    elsif ( my $svc = _get_redirect_service($doc_path) ) {
        require Cpanel::Server::Handlers::Httpd::ServiceRedirect;
        Cpanel::Server::Handlers::Httpd::ServiceRedirect->can("redirect_to_$svc")->( $self->get_server_obj(), $http_host );
    }

    elsif ( 0 == rindex( $doc_path, '/cpanelwebcall/', 0 ) ) {

        # First 15 chars are “/cpanelwebcall/”
        _serve_cpanelwebcall(
            $self->get_server_obj(),
            substr( $doc_path, 15 ),
        );
    }

    else {
        my $dot_at = index( $http_host, '.' );

        if ( -1 != $dot_at ) {
            my $leftmost_label = substr( $http_host, 0, $dot_at );

            if ( my $route = $_HOST_ROUTE{$leftmost_label} ) {
                my $mname = "_dodoc_$route";
                $self->$mname();
                return;
            }
        }

        _die_404();
    }

    return;
}

sub _get_redirect_service {
    my ($doc_path) = @_;

    for my $svc (qw( webmail  cpanel  whm )) {
        return $svc if $doc_path eq "/$svc";
        return $svc if 0 == index( $doc_path, "/$svc/" );
    }

    return undef;
}

sub _serve_cpanelwebcall ( $server_obj, $webcall_uri_piece ) {
    require Cpanel::Server::WebCalls;
    my $out = Cpanel::Server::WebCalls::handle($webcall_uri_piece);

    $server_obj->respond_200_ok_text($out);

    return;
}

sub _serve_cp_app_static {
    my ( $server_obj, $http_host, $dir, $relpath ) = @_;

    _die_404() if -1 != index $relpath, '..';

    _die_404() if !length $relpath;

    require Cpanel::Server::Handlers::Httpd::Static;
    Cpanel::Server::Handlers::Httpd::Static::handle(
        server_obj => $server_obj,
        setuid     => _determine_setuid_user_by_host($http_host),
        path       => "$dir/$relpath",
    );

    return;
}

sub _determine_setuid_user_by_host {
    my ($http_host) = @_;

    require Cpanel::Server::Handlers::Httpd::SetUid;

    return Cpanel::Server::Handlers::Httpd::SetUid::determine_setuid_user_by_host($http_host);
}

sub _die_404 {
    die Cpanel::Exception::create('cpsrvd::NotFound');
}

sub _serve_static {
    my ( $self, $http_host, $doc_path ) = @_;

    my ( $domain_owner, $docroot );

    require Cpanel::Domain::Owner;

    if ( $domain_owner = Cpanel::Domain::Owner::get_owner_or_undef($http_host) ) {
        $docroot = _get_docroot_for_http_host( $http_host, $domain_owner );
    }
    else {
        require Cpanel::Sys::Hostname;

        if ( $http_host eq Cpanel::Sys::Hostname::gethostname() ) {
            $domain_owner = 'nobody';

            require Cpanel::ConfigFiles::Apache;
            $docroot = Cpanel::ConfigFiles::Apache->new()->dir_docroot();
        }
    }

    # This is the error we’ll throw for all cases where the requested domain
    # is not one that can serve up web content: whether that’s because it’s
    # an unrecognized domain, an inactive proxy/service subdomain, or a
    # vhost config that doesn’t contain a document root.
    if ( !$docroot ) {
        _die_unknown_domain($http_host);
    }

    # For suspended accounts, just give back a simple HTTP 503.
    # We do NOT disclose the reason for the downtime.
    require Cpanel::AcctUtils::Suspended;
    if ( Cpanel::AcctUtils::Suspended::is_suspended($domain_owner) ) {
        die Cpanel::Exception::create( 'cpsrvd::ServiceUnavailable', '“[_1]” is currently not available.', [$http_host] );
    }

    require Cpanel::Server::Handlers::Httpd::Static;
    Cpanel::Server::Handlers::Httpd::Static::handle(
        server_obj => $self->get_server_obj(),
        setuid     => $domain_owner,
        path       => $docroot . $doc_path,
        size_limit => _STATIC_FILE_SIZE_SERVE_THRESHOLD(),
    );

    return;
}

sub _die_unknown_domain {
    my ($http_host) = @_;

    die Cpanel::Server::Handlers::Httpd::Errors::unknown_domain($http_host);
}

#overridden in tests
sub _is_role_enabled {
    my $module = "Cpanel::Server::Type::Role::$_[0]";

    Cpanel::LoadModule::load_perl_module($module);

    return $module->is_enabled();
}

# These are implemented as proxy connections.
sub _dodoc_proxy_cpcalendars_cpcontacts {
    my ($self) = @_;

    if ( !_is_role_enabled('CalendarContact') || Cpanel::Server::Type::is_dnsonly() ) {
        my $http_host = $self->_get_and_validate_host_header();
        _die_unknown_domain($http_host);
    }

    my $server_obj = $self->get_server_obj();

    # Something needs to have already called set_request_line()
    # and set_headers_string().
    my $reqline = $server_obj->request()->get_request_line() or do {
        die 'Need request line to send to upstream proxy!';
    };

    my $headers_text_sr = $server_obj->request()->get_headers_string() or do {
        die 'Need headers string to send to upstream proxy!';
    };

    # In the interest of simplicity, let’s send “Connection: close”
    # to the backend.
    if ( my $conn_hdr = $server_obj->request()->get_header('connection') ) {
        $conn_hdr =~ tr<A-Z><a-z>;
        if ( $conn_hdr ne 'close' ) {
            $$headers_text_sr =~ s<(\nconnection\s*:\s*)\S+><$1 close>i or do {
                warn "Failed to replace Connection header ($$headers_text_sr)";
            };
        }
    }
    else {
        substr( $$headers_text_sr, -2, 0, "Connection: close\r\n" );
    }

    my $client     = $server_obj->connection()->get_socket();
    my $fwd_header = "X-Forwarded-For: " . $self->_get_peerhost() . "\r\n";

    require Cpanel::FHUtils;
    my $read_buffer = Cpanel::FHUtils::flush_read_buffer($client);

    my $backend = _get_proxy_backend_socket();

    # Resend what we got from the client.
    syswrite( $backend, $reqline . "\r\n" . $fwd_header . $$headers_text_sr . $read_buffer );

    require Cpanel::FHUtils::Blocking;
    Cpanel::FHUtils::Blocking::set_blocking($_) for ( $backend, $client );

    # NOTE: The two one-way proxies below won’t allow for WebSocket,
    # but that’s not needed here anyway. (See Cpanel::Interconnect for a
    # proxying solution that allows that.)

    if ( my $content_length = $server_obj->request()->get_header('content-length') ) {
        $content_length -= length($read_buffer);
        if ($content_length) {
            _one_way_blocking_proxy( $client => $backend, $content_length );
        }
    }

    shutdown $backend, 1 or warn "shutdown(WR): $!";

    # This depends on cpdavd NOT keeping its TCP socket open (i.e.,
    # not using HTTP 1.1 keep-alive).
    #
    # As of September 2018 it sends the keep-alive response header
    # but doesn’t actually *do* keep-alive. Even if that gets fixed,
    # we’ve sent the “Connection: close” header, which means cpdavd
    # should always close this connection.
    _one_way_blocking_proxy( $backend => $client );

    $server_obj->connection()->shutdown_connection();

    return;
}

# Mocked in test
sub _get_peerhost {
    my ($self) = @_;
    return $self->get_server_obj()->connection()->get_socket()->peerhost();
}

sub _one_way_blocking_proxy {
    my ( $from, $to, $length ) = @_;

    require Cpanel::Autodie;

    my $buf = q<>;
    my $got;

    {
        if ( !length $buf ) {
            $got = Cpanel::Autodie::sysread_sigguard( $from, $buf, $length || 65536 );
        }

        if ( length $buf ) {
            Cpanel::Autodie::syswrite_sigguard( $to, $buf );
            $buf = q<>;
        }

        redo if $got && !$length;
    }

    return;
}

# stubbed out in tests
sub _get_proxy_backend_socket {
    my $port = $_CPCALENDAR_CPCONTACTS_LOOPBACK_PORT;

    require Cpanel::Socket::INET;
    return Cpanel::Socket::INET->new("127.0.0.1:$port");
}

sub _get_and_validate_host_header {
    my ($self) = @_;

    my $server_obj = $self->get_server_obj();

    my $http_host = $server_obj->request()->get_header('host') or do {
        die Cpanel::Exception::create_raw( 'cpsrvd::BadRequest', '“Host” header is required.' );
    };

    my $invalid_host = ( -1 != index( $http_host, '/' ) );
    $invalid_host ||= ( -1 != index( $http_host, '..' ) );
    $invalid_host ||= ( -1 != index( $http_host, "\0" ) );
    if ($invalid_host) {
        die Cpanel::Exception::create_raw( 'cpsrvd::BadRequest', "“Host” header ($http_host) is invalid." );
    }

    return $http_host;
}

sub _get_and_validate_document_relpath {
    my ($self) = @_;

    my $server_obj = $self->get_server_obj();

    my $doc = $server_obj->request()->get_document();

    return substr( $doc, 1 );
}

sub _is_mailman {
    my ($doc_path) = @_;

    if ( 0 == index( $doc_path, '/mailman/' ) ) {
        return 1 if length($doc_path) > 9;
    }
    elsif ( 0 == index( $doc_path, '/pipermail/' ) ) {
        return 1 if length($doc_path) > 11;
    }

    return 0;
}

sub _verify_autodiscover_support {
    require Cpanel::Config::LoadCpConf;
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    if ( !$cpconf_ref->{'autodiscover_proxy_subdomains'} ) {
        _die_404();
    }

    return;
}

sub _dodoc_autodiscover {
    my ($self) = @_;

    return $self->_do_autoconfig( 'outlook', $self->get_server_obj()->connection()->get_socket() );
}

sub _dodoc_autoconfig {
    return ( shift() )->_do_autoconfig('thunderbird');
}

sub _do_autoconfig {
    my ( $self, $app, @args ) = @_;

    _verify_autodiscover_support();

    require Cpanel::Email::AutoConfig;
    my ( undef, $headers, $body ) = Cpanel::Email::AutoConfig->can($app)->(@args);

    $headers =~ s<Status: ([0-9]+)(?:[^\S\r\n]+([^\r\n]+))?><> or do {
        die "invalid AutoConfig ($app) headers: $headers";
    };
    my ( $code, $reason ) = ( $1, $2 );
    $reason ||= do {
        require Cpanel::HTTP::StatusCodes;
        $Cpanel::HTTP::StatusCodes::STATUS_CODES{$code};
    };

    $reason ||= 'unknown';

    substr( $headers, 0, 0, "HTTP/1.1 $code $reason\r\nConnection: close" );

    $self->get_server_obj()->connection()->write_buffer( $headers . $body );

    return;
}

sub _get_docroot_for_http_host {
    my ( $http_host, $domain_owner ) = @_;
    require Cpanel::Config::WebVhosts;
    my $wvh = Cpanel::Config::WebVhosts->load($domain_owner);

    my $vhost_name = $wvh->get_vhost_name_for_domain($http_host);

    # get_owner_or_undef() assumes that all service (formerly proxy) subdomains are available
    # to all users at any time. Obviously that isn’t true; the function
    # below will only account for those proxy/service subdomains that are
    # actually in use for the given user ($domain_owner) at this time.
    $vhost_name ||= $wvh->get_vhost_name_for_ssl_proxy_subdomain($http_host);

    if ($vhost_name) {
        require Cpanel::Config::userdata::Load;
        my $vh_conf = Cpanel::Config::userdata::Load::load_userdata_domain_or_die( $domain_owner, $vhost_name, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );
        return $vh_conf->{'documentroot'};
    }
    return;
}

1;
