package Cpanel::DnsUtils::AskDnsAdmin;

# cpanel - Cpanel/DnsUtils/AskDnsAdmin.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::DnsUtils::AskDnsAdmin::Backend ();

use Cpanel::Debug               ();
use Cpanel::Exception           ();
use Cpanel::HTTP::ReadHeaders   ();
use Cpanel::HTTP::QueryString   ();
use Cpanel::Hulk::Constants     ();
use Cpanel::LoadModule          ();
use Cpanel::Socket::UNIX::Micro ();
use Cpanel::Autodie             ();

use constant {
    MAX_TRIES => 1 + Cpanel::DnsUtils::AskDnsAdmin::Backend::MAX_CONNECT_RETRIES,
};

our $VERSION = '3.2';

# overridden in tests
our $_SOCKET_PATH = Cpanel::DnsUtils::AskDnsAdmin::Backend::SOCKET_PATH;

our $_TEST_CONDITION;

our $MAX_TIME_TO_TRY_TO_CONNECT_TO_DNSADMIN = Cpanel::DnsUtils::AskDnsAdmin::Backend::MAX_TIME_TO_TRY_TO_CONNECT_TO_DNSADMIN;

my $_CONNECT_INTERVAL = Cpanel::DnsUtils::AskDnsAdmin::Backend::CONNECT_INTERVAL;

my ( $dns_admin_path, $socket, $socket_is_connected_to_dnsadmin, $time_last_connected, $_socket_opened_by );

my @LOCALARGS = (
    Cpanel::DnsUtils::AskDnsAdmin::Backend::ARG_LOCAL_ONLY,
    Cpanel::DnsUtils::AskDnsAdmin::Backend::ARG_REMOTE_ONLY,
    Cpanel::DnsUtils::AskDnsAdmin::Backend::ARG_CORRELATIVE,
);

our $REMOTE_AND_LOCAL = 0;
our $LOCAL_ONLY       = 1;
our $REMOTE_ONLY      = 2;    #skipself
our $CORRELATIVE      = 3;

sub askdnsadmin {
    my $res = askdnsadmin_sr(@_);
    return ref $res ? $$res : $res;
}

# Called from a mocker module:
sub _normalize_args_to_query_string ( $zone, $zonedata, $dnsuniqid, $formdata ) {
    if ( ref $formdata eq 'HASH' ) {
        $formdata = Cpanel::HTTP::QueryString::make_query_string($formdata);
    }

    $formdata ||= '';

    my $extra_form_str = Cpanel::HTTP::QueryString::make_query_string(
        {
            zone      => $zone      || undef,
            zonedata  => $zonedata  || undef,
            dnsuniqid => $dnsuniqid || undef,
        }
    );

    if ( length $formdata && substr( $formdata, -1 ) ne '&' ) {
        $formdata .= '&';
    }
    $formdata .= $extra_form_str;

    return $formdata;
}

#$formdata can be either a hashref or a string.
#If a hashref, it'll be converted to an HTTP query string.
sub askdnsadmin_sr {    ##no critic qw(ProhibitManyArgs)
    my ( $question, $local, $zone, $zonedata, $dnsuniqid, $formdata ) = @_;

    my $localarg = ( $local ? $LOCALARGS[ $local - 1 ] : '' );
    if ( !defined $localarg ) {
        die "Invalid local value: [$local]";
    }

    $formdata = _normalize_args_to_query_string( $zone, $zonedata, $dnsuniqid, $formdata );

    my @ARGS = ( $localarg ? $localarg : () );

    # If we are already connected they are not using a local dnsadmin app so
    # do not bother checking for it
    if ( !$socket_is_connected_to_dnsadmin ) {

        # If they've defined a dnsadminapp, use it;
        # otherwise (re)?connect to dnsadmin and ask.
        if ( !defined $dns_admin_path ) {
            $dns_admin_path = Cpanel::DnsUtils::AskDnsAdmin::Backend::get_dnsadminapp_path();

            $dns_admin_path //= q<>;
        }

        if ($dns_admin_path) {    # this should not be common
            return _handle_non_daemon_dnsadmin( \@ARGS, $question, \$formdata );
        }
    }

    my ( $ok, $err, $response );

    #Retry the read if the remote server goes away unexpectedly.
    for ( 1 .. MAX_TRIES ) {
        try {
            $response = _handle_daemon_dnsadmin( \@ARGS, $question, \$formdata );
            $ok       = 1;
        }
        catch {
            $err = $_;
        };

        return $response if $ok;
    }
    continue {
        _force_reconnect();
    }

    if ( try { $err->isa('Cpanel::Exception::PeerDoneWriting') } ) {
        die 'dnsadmin failed to answer a request that it accepted.';
    }

    local $@ = $err;
    die;
}

sub _get_daemon_request_payload {
    my ( $args_ar, $question, $formdata_sr ) = @_;

    my $url = Cpanel::DnsUtils::AskDnsAdmin::Backend::get_url_path_and_query( $question, @$args_ar );

    my @headers = (
        'Content-Length: ' . length($$formdata_sr),
    );

    my @extra_headers = Cpanel::DnsUtils::AskDnsAdmin::Backend::get_headers();
    push @headers, map { "$_->[0]: $_->[1]" } @extra_headers;

    return \join(
        "\r\n",
        "POST $url HTTP/1.0",
        @headers,
        q<>,
        $$formdata_sr,
    );
}

#overridden in tests to handle the non-daemon case
#NB: We can’t use HTTP::Tiny::UNIX here because we conserve the
#socket connection.
sub _handle_daemon_dnsadmin {
    my ( $args_ar, $question, $formdata_sr ) = @_;

    # force a reconnection if not connected or time has expired
    _force_reconnect() if _need_to_reconnect();

    if ( !$socket_is_connected_to_dnsadmin ) {

        # we should never fall through to here #
        die 'failed to connect to dnsadmin but no exception was thrown from _force_reconnect';
    }

    #Do this so we avoid SIGPIPE and get EPIPE instead,
    #which will propagate as an exception.
    local $SIG{'PIPE'} = sub { };

    my $to_write_ref = _get_daemon_request_payload( $args_ar, $question, $formdata_sr );

    my $bytes_written = 0;

    while ( $bytes_written < length $$to_write_ref ) {
        $bytes_written += Cpanel::Autodie::syswrite_sigguard(
            $socket,
            substr( $$to_write_ref, $bytes_written ),
        );
    }

    my ( $hdr_txt, $body ) = Cpanel::HTTP::ReadHeaders::read($socket);

    my %HEADERS;
    {
        %HEADERS = map { ( lc $_->[0], substr( $_->[1] || '', 0, 8190 ) ) }    # lc the header and truncate the value to 8190 bytes - values which are false can safely

          # be converted to an empty string since they should never
          # happen (this is an optimization)
          map { [ ( split( /:\s*/, $_ || '', 2 ) )[ 0, 1 ] ] }    # split header into name, value - and place into an arrayref for the next map to alter
          split( /\r?\n/, $$hdr_txt );                            # split each header
    }

    my $bytes_to_read = int( $HEADERS{'content-length'} || 0 ) - length $$body;

    #Compare with 0 explicitly in case the actual body
    #is longer than the Content-Length header’s value.
    while ( $bytes_to_read > 0 ) {
        my $bytes_read = Cpanel::Autodie::sysread_sigguard( $socket, $$body, $bytes_to_read, length $$body );

        die Cpanel::Exception::create('PeerDoneWriting') if !$bytes_read;

        $bytes_to_read -= $bytes_read;
    }

    # Keep the socket around because we may just make another request
    #close($socket);
    #$socket_is_connected_to_dnsadmin=0;
    return $body;
}

sub _need_to_reconnect {
    return 1 if !$socket_is_connected_to_dnsadmin    #
      || $_socket_opened_by ne "$$-$>"               # opened by a different process / user
      || _time_has_expired()                         # max lifetime for the socket
      ;
    return;
}

sub _handle_non_daemon_dnsadmin {
    my ( $args_ar, $question, $formdata_sr ) = @_;

    # do not need to purge the cache when dnsadmin is not run as a daemon
    if ( $question eq 'RESET_CACHE' ) {
        warn "“$question” is useless when dnsadmin is not run as a daemon.";
        return undef;
    }

    # this should not be common
    Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Object');

    my ( $stdin, @run_args );

    if ( length($$formdata_sr) > 100000 ) {    #handle ARG_MAX
        $stdin = "$question\n$$formdata_sr";
    }
    else {
        @run_args = ( '--action' => $question, '--data' => $$formdata_sr );
    }

    push @run_args, @$args_ar;

    my $run = Cpanel::SafeRun::Object->new_or_die(
        program  => $dns_admin_path,
        args     => \@run_args,
        keep_env => 1,                 # we must pass REMOTE_ADDR, REMOTE_USER
        ( $stdin ? ( stdin => \$stdin ) : () ),
    );

    return $run->stdout_r();
}

sub _time_has_expired {
    return time() - $time_last_connected > 115;    # This should always be at least 5s less than the smaller of dnsadmin's $DNSADMIN_CHILD_TIMEOUT or $local_timeout ($DEFAULT_DNSADMIN_LOCAL_TIMEOUT)
}

sub _close_socket {
    $socket_is_connected_to_dnsadmin = 0;
    if ( $socket && fileno $socket ) {
        close($socket) or Cpanel::Debug::log_warn("Failed to close dnsadmin socket: $!");
    }

    return;
}

sub _create_socket_or_die {
    my $socket_ok = socket(
        $socket,
        $Cpanel::Hulk::Constants::AF_UNIX,
        $Cpanel::Hulk::Constants::SOCK_STREAM,
        0,
    );

    if ( !$socket_ok ) {
        die Cpanel::Exception::create( 'IO::SocketOpenError', [ 'domain' => $Cpanel::Hulk::Constants::AF_UNIX, 'type' => $Cpanel::Hulk::Constants::SOCK_STREAM, protocol => 0, 'error' => $! ] );
    }

    return;
}

sub _usock {
    return Cpanel::Socket::UNIX::Micro::micro_sockaddr_un($_SOCKET_PATH);
}

sub _connect_socket {
    return if !connect( $socket, _usock() );

    $socket_is_connected_to_dnsadmin = 1;
    $_socket_opened_by               = "$$-$>";
    $time_last_connected             = time();

    return 1;
}

#This only returns or die()s.
sub _force_reconnect {
    _close_socket();

    _create_socket_or_die();

    return if _connect_socket();

    _restartsrv("The system failed to connect to “$_SOCKET_PATH”: $!");

    my $max_attempts = $> == 0 ? 2 : 1;
    my $err;
    foreach my $attempt ( 1 .. $max_attempts ) {
        $err = undef;

        try {
            _dnsadmin_connect();
        }
        catch {
            $err = $_;
        };

        if ( !$err ) {
            return;
        }

        _restartsrv($err) if $attempt < $max_attempts;
    }

    # connect() will give ECONNREFUSED if $_SOCKET_PATH exists
    # but is not a socket with a listener. It’s useful to report
    # this state if it happens so we can distinguish it from the
    # case where the path is a socket but no process accepted
    # the connection.
    if ( !-S $_SOCKET_PATH ) {
        my $err_part = $! ? " ($!)" : q<>;
        warn "“$_SOCKET_PATH” is still not a local socket after trying to restart dnsadmin$err_part!";
    }

    local $@ = $err;
    die;
}

sub _dnsadmin_connect {
    return if _connect_socket();

    local $!;
    require Cpanel::TimeHiRes;
    for ( 1 .. ( $MAX_TIME_TO_TRY_TO_CONNECT_TO_DNSADMIN / $_CONNECT_INTERVAL ) ) {
        Cpanel::TimeHiRes::sleep($_CONNECT_INTERVAL);
        return if _connect_socket();
    }

    die Cpanel::Exception::create( 'IO::SocketConnectError', [ 'to' => _usock(), 'error' => $! ] );

}

#mocked in tests
sub _restartsrv {
    my ($err) = @_;
    Cpanel::Debug::log_warn( "The system had to unexpectedly restart dnsadmin because it could not connect: " . Cpanel::Exception::get_string($err) );

    Cpanel::DnsUtils::AskDnsAdmin::Backend::restart_service();

    return;
}

#for testing
sub _clear_dnsadminapp {
    $dns_admin_path = undef;
    return;
}

#for testing
sub _clear_socket {
    $socket_is_connected_to_dnsadmin = undef;
    $socket                          = undef;
    $time_last_connected             = undef;
    $_socket_opened_by               = undef;

    return;
}

END {
    _clear_socket();
}

1;
