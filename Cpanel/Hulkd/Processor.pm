package Cpanel::Hulkd::Processor;

# cpanel - Cpanel/Hulkd/Processor.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This module's tests are heavily implementation-dependent.
#----------------------------------------------------------------------

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) - not fully vetted for warnings

use Try::Tiny;

require Cpanel::Hulk::Cache::IpLists;
require Cpanel::Hulk::Key;
require Cpanel::Config::Hulk;
require Cpanel::Config::Hulk::Load;
require Cpanel::IP::Convert;
require Cpanel::IP::Expand;
require Cpanel::IP::Parse;
require Cpanel::IP::LocalCheck;    # previously used Cpanel::DIp legacy code (slow)
require Cpanel::Hulk::Constants;
require Cpanel::Hulk::Utils;
require Cpanel::LocaleString;
require Cpanel::JSON;
require Cpanel::Hulk;
require Cpanel::ServerTasks;
require Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser::Adder;
require Cpanel::Hulkd::QueuedTasks::BlockBruteForce::Adder;
require Cpanel::Hulkd::QueuedTasks::NotifyLogin::Adder;

use Cpanel::Exception ();

our $TIMEZONESAFE_FROM_UNIXTIME = "DATETIME(?, 'unixepoch', 'localtime')";
our $TIMEZONESAFE_LOGINTIME     = "STRFTIME('%s',LOGINTIME,'utc') as LOGINTIME";
our $TIMEZONESAFE_EXPTIME       = "STRFTIME('%s',EXPTIME,'utc') as EXPTIME";

our $EXCESSIVE_BRUTE_FORCE_LOCKOUT_TIME    = 86400;    # 1 DAY
our $TIME_BETWEEN_GOOD_LOGIN_NOTIFICATIONS = 86400;    # 1 DAY
our $REPORT_INLINE                         = 1;
our $REPORT_BLOCK                          = 0;

our $COUNT_CURRENT_REQUEST_AS_OK  = 0;
our $COUNT_CURRENT_REQUEST_AS_HIT = 1;

our $CONNECTION_STATE_READ  = 0;
our $CONNECTION_STATE_WRITE = 1;

our $FIRST_HTTP_REQUEST_READ_TIMEOUT           = 15;
our $KEEPALIVE_HTTP_REQUEST_READ_TIMEOUT       = 10;
our $MAXIMUM_TIME_FOR_A_REQUEST_TO_BE_SERVICED = 60;

our $conf_ref = {};

my $conf_mtime = 0;

sub _REQUEST_KEY_HUMAN_READABLE_NAMES {
    return (
        'remote_ip'   => Cpanel::LocaleString->new('Remote IP Address'),
        'local_ip'    => Cpanel::LocaleString->new('Local IP Address'),
        'service'     => Cpanel::LocaleString->new('Authentication Database'),
        'authservice' => Cpanel::LocaleString->new('Service'),
        'user'        => Cpanel::LocaleString->new('Username'),
        'local_port'  => Cpanel::LocaleString->new('Local Port'),
        'remote_port' => Cpanel::LocaleString->new('Remote Port'),
        'local_user'  => Cpanel::LocaleString->new('Local User triggering request'),

        # For debug only
        #    'authtoken_hash' => Cpanel::LocaleString->can('new')->('Cpanel::LocaleString', 'Hashed Auth Token'),
    );
}

#STATIC METHOD
#
#Accepts no arguments.
#
#NOTE: Will warn() if cPHulk config is out of whack.
#
sub initialize {
    my $conf_path          = Cpanel::Config::Hulk::get_conf_path();
    my $on_disk_conf_mtime = ( stat($conf_path) )[9] || time();       # Default to now if there is no config file

    if ( $on_disk_conf_mtime > $conf_mtime ) {
        $conf_mtime = $on_disk_conf_mtime;
        %{$conf_ref} = %{ scalar Cpanel::Config::Hulk::Load::loadcphulkconf() };
    }

    return 1;
}

sub new {
    my ( $class, $hulkd_object, $socket ) = @_;

    die "new requires a Cpanel::Hulkd object." if !UNIVERSAL::isa( $hulkd_object, 'Cpanel::Hulkd' );

    return bless {
        'hulkd'            => $hulkd_object,             #
        'conf'             => $conf_ref,
        'socket'           => $socket,                   #
        'state'            => 'preauth',                 #
        'connection_state' => $CONNECTION_STATE_WRITE,
      },
      $class;
}

#This gets invoked directly from tests. :-(
sub _run_http {
    my ($self) = @_;

    # See Protocol examples: https://wiki2.dovecot.org/Authentication/Policy

    # Note: _run_http does not currently do anything with $from_dormant
    # as http requests do not send a welcome banner like the 220
    # we do over the unix socket

    local $0 = "$0 - http socket";
    $self->{'protocol'}         = 'http';
    $self->{'checked_password'} = 0;
    $self->{'hulkd'}->debug("run_http");
    local $SIG{'PIPE'} = sub {
        die "exiting on sigpipe (disconnect)";
    };
    my $request_count = 0;

    local $SIG{'ALRM'} = sub {
        die Cpanel::Exception::create( 'Timeout', 'Timeout while reading HTTP connection' );
    };

    my $waiting_for_request_start;

    my $return = 1;

    try {
      HTTP:
        while ( $self->{'socket'} ) {
            $waiting_for_request_start = 1;
            alarm( ++$request_count == 1 ? $FIRST_HTTP_REQUEST_READ_TIMEOUT : $KEEPALIVE_HTTP_REQUEST_READ_TIMEOUT );
            my $getreq = $self->_read_http_get_request() or do {
                $return = 0;
                last HTTP;
            };
            $waiting_for_request_start = 0;

            my $headers_ref = $self->_read_http_headers();

            # my ( $uri, $query_string );
            # We don't need to parse
            # $getreq =~ s/[\r\n]+$//;
            # ( $uri, $query_string ) = split( /\?/, ( split( /\s+/, $getreq ) )[1], 2 );

            my $buffer = $self->_read_http_body($headers_ref);
            alarm($MAXIMUM_TIME_FOR_A_REQUEST_TO_BE_SERVICED);
            $self->_check_password_in_x_api_key_header($headers_ref) or do {
                $return = 0;
                last HTTP;
            };
            $self->_handle_action( $buffer, { 'action' => ( index( $getreq, q{command=allow} ) > -1 ? 'PRE' : 'LOGIN' ) } );

            $getreq = '';

            # Look for Connection: close, or Connection: Close
            last HTTP if $headers_ref->{'connection'} && index( $headers_ref->{'connection'}, 'lose' ) > -1;    # Connection: close

            # handle another request if possible
        }
    }
    catch {

        #Dovecot likes to sit and just keep a connection open. But cphulk
        #doesn’t like that and throws SIGALRM to stop the read and close the
        #socket. For this typical case, we do NOT want to spew into the log
        #since this is normal operation. We *do* throw if we’ve gotten part
        #of the next request or if we haven’t gotten any requests, since
        #those indicate that something is wrong.
        my $to_die = !$waiting_for_request_start;
        $to_die ||= $request_count < 2;
        $to_die ||= !try { $_->isa('Cpanel::Exception::Timeout') };

        if ($to_die) {
            local $@ = $_;
            die;
        }
    };

    return $return;

}

sub _read_http_body {
    my ( $self, $headers_ref ) = @_;
    my $content_length = int( $headers_ref->{'content-length'} ) || 0;
    my $remain         = $content_length;
    my $buffer         = '';
    $self->{'hulkd'}->debug("reading 1[$remain]");
    while ( $remain > 0 && $self->{'socket'}->read( $buffer, $remain, length $buffer ) ) {
        $self->{'hulkd'}->debug("reading [$remain]");
        $remain = $content_length - length $buffer;
    }
    $self->{'hulkd'}->debug("buffer $buffer");
    return $buffer;
}

sub _check_password_in_x_api_key_header {
    my ( $self, $headers_ref ) = @_;

    return 1 if $self->{'checked_password'};

    my ( $user, $pass ) = split( m{:}, $headers_ref->{'x-api-key'} );

    if ( $self->_check_connect_pass( $user, $pass ) ) {
        $self->{'hulkd'}->debug("x-api-key http auth good for service: $user");
        $self->{'login_service'}    = $user;
        $self->{'state'}            = 'authed';
        $self->{'checked_password'} = 1;
        return 1;
    }
    $self->{'hulkd'}->errlog("x-api-key http auth failed for service: $user");
    $self->_send_response( 400, 'AUTH FAILED' );
    return 0;
}

sub _read_http_headers {
    my ($self) = @_;
    my %HEADERS;
    {
        local $/ = "\r\n\r\n";
        %HEADERS = map { ( lc $_->[0], substr( $_->[1], 0, 8190 ) ) }    # lc the header and truncate the value to 8190 bytes
          map { [ ( split( /:\s*/, $_, 2 ) )[ 0, 1 ] ] }                 # split header into name, value - and place into an arrayref for the next map to alter
          split( /\r?\n/, readline( $self->{'socket'} ) );               # split each header
    }
    return \%HEADERS;
}

sub _read_http_get_request {
    my ($self) = @_;
    my $getreq;

    local $/ = "\r\n";
    while ( !length $getreq ) {

        $self->{'hulkd'}->debug("reading");
        $getreq = readline( $self->{'socket'} );
        $self->{'hulkd'}->debug("getreq[@{[length($getreq) || '']}]");

        if ($getreq) {
            if ( $getreq =~ /^[\r\n]*$/ ) {
                $getreq = '';
                next;
            }
            return $getreq;
        }

        # Remote client disconnect
        return undef;
    }
    return undef;
}

sub run {
    my ( $self, $from_dormant ) = @_;

    $self->{'serviced_non_dormant_request'} = 0;
    my $sockname = $self->{'socket'}->sockname();
    my ($sock_type) = unpack( 'Sn10', $sockname );
    $self->{'hulkd'}->debug( "socket type: " . $sock_type );

    try {
        if ( $sock_type != $Cpanel::Hulk::Constants::AF_UNIX ) {
            $self->_run_http();
        }
        else {
            $self->_run_unix($from_dormant);
        }
    }
    catch {
        my $err = $_;

        if ( $self->{'socket'} && $self->{'connection_state'} == $CONNECTION_STATE_WRITE ) {
            $self->_send_response( -1, 'INTERNAL FAILURE' );
        }
        $self->{'hulkd'}->errlog( "Internal Failure (state:$self->{'state'} login_service:$self->{'login_service'}): " . Cpanel::Exception::get_string_no_id($err) );
    };

    $self->{'hulkd'}->debug("Shutdown Socket");
    $self->{'socket'}->close() if $self->{'socket'};
    alarm 0;

    return $self->{'serviced_non_dormant_request'};
}

sub _run_unix {
    my ( $self, $from_dormant ) = @_;

    # Protocol Example:
    #
    # SERVER>> 220 cPHulkd Ready. AUTH required.<CRLF>
    # CLIENT>> AUTH pam wbCl5Adjwdksjdsl<CRLF>
    # SERVER>> 200 AUTH OK<CRLF>
    # CLIENT>> ACTION {"action":"PAM_SETCRED", "auth_database":"system", "username":"root", "remote_host":"10.1.4.3", "status":1, "login_time":1489515317, "quit_after":1, "local_port":0, "remote_user":null, "auth_service":"sshd", "tty":"ssh", "authtoken_hash":null}<CRLF>
    # SERVER>> 200 LOGIN OK (WHITELIST=0)<CRLF>
    #

    alarm($MAXIMUM_TIME_FOR_A_REQUEST_TO_BE_SERVICED);
    local $0 = "$0 - unix socket";
    if ( !$from_dormant ) {
        $self->{'socket'}->send( qq{220 cPHulkd Ready. AUTH required.\r\n}, 0 );
    }

    $self->{'hulkd'}->debug("run unix");
    $self->{'protocol'} = 'hulk';
    while ( my $line = readline $self->{'socket'} ) {
        $self->{'connection_state'} = $CONNECTION_STATE_WRITE;
        chomp($line);
        $self->{'hulkd'}->debug("Input Request: [$line]");
        if ( $line =~ m/^AUTH\s+(\S+)\s+(\S+)/ ) {    #AUTH exim [pass]
            $self->_send_response( 200, 'AUTH OK' );
        }
        elsif ( $line =~ m/^(?:ACTION)/ ) {
            $self->_handle_action( ( split( m{ }, $line, 2 ) )[-1] ) || last;    # must be a single space to handle empty args
        }
        elsif ( $line =~ m/^(PRE|LOGIN|PAM_AUTHENTICATE|PAM_SETCRED)/ ) {
            $self->{'hulkd'}->errlog("Client sent legacy action: [$1]");
            $self->_handle_op( split( m{ }, $line ) ) || last;                   # must be a single space to handle empty args
        }
        elsif ( $line =~ m/^QUIT/ ) {

            # Don't complain if the other side has already hung up.
            local $SIG{'PIPE'} = 'IGNORE';
            local $self->{'_ignore_write_failure'} = 1;
            $self->_send_response( 220, 'QUIT GOODBYE' );
            last;
        }
        else {
            local $SIG{'PIPE'} = 'IGNORE';
            local $self->{'_ignore_write_failure'} = 1;
            $self->_send_response( 300, 'INVALID IN CURRENT STATE' );
            last;
        }
    }
    return 1;
}

# Various handlers for specific commands
#
sub _handle_op {
    my ( $self, @packed ) = @_;

    chomp( $packed[-1] );

    #PRE system nick 10.1.4.23 1 1392150917 0 208
    #LOGIN system nick 10.1.4.23 1 1392150919 1 2087
    # PRE|LOGIN [service AUTH DATABASE - ie: mail, system] bob [REMOTEIP:REMOTEPORT] STATUS=[1|0] LOGINTIME=[1|0] QUIT_AFTER=[1|0] [REMOTEPORT] [LOCALUSER] [AUTHSERVICE ie imap, pure-ftpd] [TOKEN-MD5] [LOCALIP:LOCALPORT] [LOCALPORT]

    my ( $input_op, $input_service, $input_user, $input_remote_ipdata, $input_status, $input_logintime, $input_quit_after, $input_remote_port, $input_ruser, $input_authservice, $input_tty, $input_authtoken_hash, $input_local_ipdata, $input_local_port ) = @packed;

    my %input = (
        'action'         => $input_op,
        'auth_database'  => $input_service,
        'username'       => $input_user,
        'remote_host'    => $input_remote_ipdata,
        'status'         => $input_status,
        'login_time'     => $input_logintime,
        'quit_after'     => $input_quit_after,
        'remote_port'    => $input_remote_port,
        'remote_user'    => $input_ruser,
        'auth_service'   => $input_authservice,
        'tty'            => $input_tty,
        'authtoken_hash' => $input_authtoken_hash,
        'local_host'     => $input_local_ipdata,
        'local_port'     => $input_local_port,
    );
    chomp($input_user);

    return $self->_handle_input( \%input );
}

sub _handle_action {
    my ( $self, $action_json, $merge ) = @_;

    my ( $input, $error_reason );
    try {
        $input = Cpanel::JSON::Load($action_json);
    }
    catch {
        $error_reason = "Failed to decode JSON data";
    };
    if ($merge) {
        @{$input}{ keys %$merge } = values %$merge;
    }

    if ($error_reason) {
        $self->_send_response( 400, "Unable to decode json: $error_reason." );
        die "Unable to decode json: $error_reason";
    }
    elsif ( ref $input ne 'HASH' ) {
        $self->_send_response( 400, "Invalid json data." );
        die "Invalid json data.";
    }

    return $self->_handle_input($input);
}

sub _handle_input {    ## no critic qw(Subroutines::ProhibitExcessComplexity) -- requires a larger refactor to address complexity
    my ( $self, $input ) = @_;

    if ( ( !$input->{'remote_host'} || $input->{'remote_host'} eq '(null)' ) && $input->{'tty'} ) {
        my $utmp_ipdata = $self->_lookup_ipdata_from_tty( $input->{'username'}, $input->{'tty'} );
        $input->{'remote_host'} = $utmp_ipdata if $utmp_ipdata;
    }

    my $remote_ip_version  = 4;
    my $parsed_remote_ip   = $input->{'remote_host'} || '';
    my $parsed_remote_port = $input->{'remote_port'} || '';
    my $local_ip_version   = 4;
    my $parsed_local_ip    = $input->{'local_host'} || '';
    my $parsed_local_port  = $input->{'local_port'} || '';

    if ( $input->{'remote_host'} ) {
        ( $remote_ip_version, $parsed_remote_ip, $parsed_remote_port ) = Cpanel::IP::Parse::parse( $input->{'remote_host'}, $input->{'remote_port'} );
    }
    if ( $input->{'local_host'} ) {
        ( $local_ip_version, $parsed_local_ip, $parsed_local_port ) = Cpanel::IP::Parse::parse( $input->{'local_host'}, $input->{'local_port'} );
    }

    my $local_user     = $input->{'remote_user'};
    my $ip_is_loopback = $parsed_remote_ip ? Cpanel::IP::LocalCheck::ip_is_on_local_server($parsed_remote_ip) : 0;
    if ( !$local_user && $ip_is_loopback && $parsed_remote_ip && $parsed_remote_port && $parsed_local_ip && $parsed_local_port ) {
        require Cpanel::Ident;
        my $uid = Cpanel::Ident::identify_local_connection( $parsed_remote_ip, $parsed_remote_port, $parsed_local_ip, $parsed_local_port );
        if ( defined $uid ) {
            $local_user = ( getpwuid($uid) )[0];
        }
    }

    my $human_readable_remote_ip = length $parsed_remote_ip ? Cpanel::IP::Convert::binip_to_human_readable_ip( Cpanel::IP::Convert::ip2bin16($parsed_remote_ip) ) : '';
    my $human_readable_local_ip  = length $parsed_local_ip  ? Cpanel::IP::Convert::binip_to_human_readable_ip( Cpanel::IP::Convert::ip2bin16($parsed_local_ip) )  : '';
    my $authservice              = ( $input->{'auth_service'} || $self->{'login_service'} || $input->{'auth_database'} );

    if ( !length $human_readable_remote_ip || $human_readable_remote_ip eq '0000:0000:0000:0000:0000:0000:0000:0000' || $human_readable_remote_ip eq '0.0.0.0' ) {
        if ( length $human_readable_remote_ip ) {
            $self->{'hulkd'}->errlog("The service:[$authservice] unexpectedly sent the invalid remote IP address:[$parsed_remote_ip]. (Consider disabling DNS resolution for this service)");
        }
        $parsed_remote_ip         = undef;    # Some versions of pam will return the IP address as (null)
        $human_readable_remote_ip = '';
        $ip_is_loopback           = 1;        # treat the connection as local in the event we do not have a valid ip
    }
    if ( !length $human_readable_local_ip || $human_readable_local_ip eq '0000:0000:0000:0000:0000:0000:0000:0000' || $human_readable_local_ip eq '0.0.0.0' ) {
        if ( length $human_readable_local_ip ) {
            $self->{'hulkd'}->errlog("The service:[$authservice] unexpectedly sent the invalid local IP address:[$parsed_local_ip]. (Consider disabling DNS resolution for this service)");
        }
        $parsed_local_ip         = undef;     # Some versions of pam will return the IP address as (null)
        $human_readable_local_ip = '';
    }

    # Dovecot provides the status in the success field
    if ( exists $input->{'success'} ) {
        $input->{'status'} = $input->{'success'} ? 1 : 0;
    }
    if ( index( $input->{'username'}, '/' ) > -1 ) {    # maibox_path_addition or tempuser postfix
        $input->{'username'} = ( split( m{/}, $input->{'username'}, 2 ) )[0];
    }

    $self->{'request'} = {
        'user'                   => substr( $input->{'username'}, 0, 128 ),
        'logintime'              => int( $input->{'login_time'} || time() ),
        'status'                 => ( $input->{'action'} eq 'PRE' ? 1 : ( $input->{'status'} || 0 ) ),
        'local_port'             => $parsed_local_port,
        'remote_port'            => $parsed_remote_port,
        'ip_bin16'               => Cpanel::IP::Expand::ip2binary_string($parsed_remote_ip),
        'ip_version'             => $remote_ip_version,
        'ip_is_loopback'         => $ip_is_loopback,
        'ip_is_whitelisted'      => 0,
        'country_is_whitelisted' => 0,
        'ip_is_blacklisted'      => 0,
        'country_is_blacklisted' => 0,
        'local_user'             => $local_user,
        'quit_after'             => ( $input->{'quit_after'} ? 1 : 0 ),
        'op'                     => $input->{'action'},
        #
        # AKA the password database service
        'service' => $input->{'auth_database'},

        # AKA the name of the service requesting authentication i.e. 'sudo','sshd','cpsrvd' etc.
        'authservice' => $authservice,

        # normalize the display of the IP address
        'remote_ip' => $human_readable_remote_ip,
        'local_ip'  => $human_readable_local_ip,

        # See the note below as this removes the failed login that PAM_AUTHENTICATE adds once PAM_SETCRED happens.
        'forget_auth_failures_on_login' => ( $input->{'action'} eq 'PRE' ? 0 : 1 ),

        # A hit is a "strike" against the account/ip
        # If 2FA security policy is enabled on the server, then we always count attempts as hits
        'is_hit' => $self->{'hulkd'}->{'tfa_enabled'} ? 1 : 0,
    };

    if ( index( $input->{'username'}, '__cpanel__service__auth_' ) == 0 ) {

        # Since _check_password_in_x_api_key_header() runs before we get here,
        # the "service auth" for any http calls is already done.
        #
        # So it is safe to do what cphulkd-dormant does here and respond right way,
        # without having to hit the DB - which lets us avoid the DBREAD calls, that
        # would keep cphulkd from going dormant for these service checks.
        #
        # This is where chkservd status requests are handled. We need to check that the
        # dbprocessor process is running also. If dbprocessor is not running we return
        # an error so chkservd will restart the service.

        require Cpanel::Hulkd::Daemon;
        if ( Cpanel::Hulkd::Daemon::get_db_proc_pid() ) {
            $self->_send_response( 200, "LOGIN OK (WHITELIST=1)" );
        }
        else {
            $self->_send_response( -1, "dbprocessor is down." );

        }

        return $self->{'request'}{'quit_after'} ? 0 : 1;
    }
    else {
        if ( $input->{'action'} eq 'PRE' || $input->{'action'} eq 'PAM_SETCRED' ) {
            $self->{'request'}{'status'} = 1;
        }
        elsif ( $input->{'action'} eq 'PAM_AUTHENTICATE' ) {
            $self->{'request'}{'status'} = 0;
        }
        else {
            $self->{'request'}{'status'} = ( $input->{'status'} || 0 );
        }

        $self->{'serviced_non_dormant_request'} = 1;
    }

    # AKA the password hashed
    if ( length $input->{'authtoken_hash'} ) {
        my $salted_token;
        if ( Cpanel::Hulk::Utils::token_is_hashed( $input->{'authtoken_hash'} ) ) {
            $salted_token = $input->{'authtoken_hash'};
        }
        else {    # Token needs to be hashed
            $salted_token = Cpanel::Hulk::Utils::hash_authtoken( $input->{'authtoken_hash'}, $self->{'request'}{'logintime'}, $self->{'request'}{'user'}, $self->{'request'}{'remote_ip'} );
        }
        $self->{'request'}{'authtoken_hash'} = Cpanel::Hulk::Utils::strip_salt_from_hashed_token($salted_token);
    }

    $self->_lookup_ip_in_lists();

    $self->{'hulkd'}->debug("Authentication from IP $self->{'request'}{'remote_ip'}, IP is whitelisted? $self->{'request'}{'ip_is_whitelisted'}, Country is whitelisted? $self->{'request'}{'country_is_whitelisted'}, IP is blacklisted? $self->{'request'}{'ip_is_blacklisted'}, Country is blacklisted? $self->{'request'}{'country_is_blacklisted'}");

    return $self->_handle_authentication_request();
}

sub _handle_authentication_request {
    my ($self) = @_;

    # Handling whitelist and blacklist ips must use this match order
    # 1. IP is WHITELISTED.
    # 2. COUNTRY is WHITELISTED.
    # 3. IP is BLACKLISTED.
    # 4. COUNTRY IS BLACKLISTED.

    # Know ops
    # PAM_SETCRED - Called when pam succcessfully authenticates someone (status is always 1)
    # PAM_AUTHENTICATE - Called when pam does an authentication to see if the login should be blocked
    # PRE - Test to see if hulk will block us before we try to login (status is always 1)
    # LOGIN - Called with the status of an actual login.
    if ( $self->{'request'}{'op'} eq 'PAM_SETCRED' || $self->{'request'}{'ip_is_whitelisted'} || $self->{'request'}{'country_is_whitelisted'} ) {

        # Ensure requests from whitelisted hosts aren't counted as hits.
        if ( $self->{'request'}{'ip_is_whitelisted'} || $self->{'request'}{'country_is_whitelisted'} ) {
            $self->{'request'}{'is_hit'} = 0;
        }

        $self->_send_response( 200, "LOGIN OK (WHITELIST=$self->{'request'}{'ip_is_whitelisted'}, COUNTRY_WHITELIST=$self->{'request'}{'country_is_whitelisted'})" );
        $self->_handle_login_ok();
    }
    elsif ( $self->{'request'}{'ip_is_blacklisted'} ) {

        # If the IP address is already blacklisted, then do not
        # consider it to be a 'hit' - i.e., do not bump the failed login count.
        $self->{'request'}{'is_hit'} = 0;

        # Once we match a blacklisted IP we need to call
        # _ip_based_brute_force_triggered in case they want
        # an iptables rule which will prevent this function from
        # being triggered over and over again
        $self->_ip_based_brute_force_triggered(
            'excessive_failures' => '1',
            'ip_is_blacklisted'  => 1,
            'current_failures'   => 1,
        );    # one day block
        $self->_send_response( 580, 'LOGIN DENIED -- IP IS BLACKLISTED' );
        $self->_log_blocked( 'reason' => 'The IP address is blacklisted.' );
    }
    elsif ( $self->{'request'}{'country_is_blacklisted'} ) {

        # If the country the IP address is in already blacklisted, then do not
        # consider it to be a 'hit' - i.e., do not bump the failed login count.
        $self->{'request'}{'is_hit'} = 0;

        # Once we match an IP in a blacklisted country we need to call
        # _ip_based_brute_force_triggered in case they want
        # an iptables rule which will prevent this function from
        # being triggered over and over again
        $self->_ip_based_brute_force_triggered(
            'excessive_failures'     => '1',
            'country_is_blacklisted' => 1,
            'current_failures'       => 1,
        );    # one day block
        $self->_send_response( 580, 'LOGIN DENIED -- COUNTRY IS BLACKLISTED' );
        $self->_log_blocked( 'reason' => 'The country is blacklisted.' );
    }

    elsif ( $self->_is_marked_as_brute($Cpanel::Config::Hulk::LOGIN_TYPE_EXCESSIVE_BRUTE) ) {
        $self->_send_response( 580, 'LOGIN DENIED -- EXCESSIVE FAILURES -- IP TEMP BANNED' );
        $self->_log_blocked( 'reason' => 'The IP address is marked as an excessive brute.', 'exptime' => $self->_get_last_brute_expire_time($Cpanel::Config::Hulk::LOGIN_TYPE_EXCESSIVE_BRUTE) );
        $self->{'request'}{'is_hit'} = 1 if !$self->{'request'}{'status'};
    }
    elsif ( $self->{'request'}{'op'} eq 'PAM_AUTHENTICATE' ) {

        # pam authenicate adds a failure with a specific time.
        # pam setcred which is called when pam says everything is ok to login
        # will call deregister_failed_login to get rid of the failed attempt
        # because it really was ok.
        $self->{'request'}{'is_hit'} = 1;

        if ( my $hulk_code = $self->_auth_request_triggers_brute_force_protection($COUNT_CURRENT_REQUEST_AS_OK) ) {    # We don't know if the current request is OK because we can't predict of PAM_SETCRED will be called
                                                                                                                       # so we do not count it against them yet.
            $self->_send_response( $hulk_code, 'LOGIN DENIED -- TOO MANY FAILURES' );
        }
        else {
            $self->_send_response( 200, 'OK TO CONTINUE' );
        }
    }
    elsif ( $self->{'request'}{'status'} ) {    # Successful authentication or PRE here
        if ( my $hulk_code = $self->_auth_request_triggers_brute_force_protection($COUNT_CURRENT_REQUEST_AS_OK) ) {
            $self->_send_response( $hulk_code, 'LOGIN DENIED -- TOO MANY FAILURES' );
        }
        else {
            # If we have a good login, then don't consider the current request
            # as a hit.
            $self->{'request'}{'is_hit'} = 0;
            $self->_send_response( 200, "LOGIN OK (WHITELIST=$self->{'request'}{'ip_is_whitelisted'}, COUNTRY_WHITELIST=$self->{'request'}{'country_is_whitelisted'})" );
            $self->_handle_login_ok();
        }
    }
    else {    # status == 0
        $self->{'request'}{'is_hit'} = 1;

        # Failed authentication past here - Current only LOGIN gets here when status == 0.  This is always a hit
        if ( my $hulk_code = $self->_auth_request_triggers_brute_force_protection($COUNT_CURRENT_REQUEST_AS_HIT) ) {    # Status is 0 so we count the current request against them
            $self->_send_response( $hulk_code, 'LOGIN DENIED -- TOO MANY FAILURES' );
        }
        else {
            $self->_send_response( 500, 'LOGIN DENIED -- STATUS=0' );
        }
    }

    # Record failed logins
    if ( $self->{'request'}{'is_hit'} && !$self->{'request'}{'status'} ) {
        $self->_register_failed_login();
        $self->{'hulkd'}->debug( "Registering " . $self->_request_report($REPORT_INLINE) );
    }
    else {
        $self->{'hulkd'}->debug( "NOT Registering " . $self->_request_report($REPORT_INLINE) );
    }
    return $self->{'request'}{'quit_after'} ? 0 : 1;
}

# END- Various handlers for specific commands

# These functions rely on the state of the request

sub _auth_request_triggers_brute_force_protection {
    my ( $self, $count_current_request_as_hit ) = @_;

    # Determine if we actually need to check the IP Address for failure
    # attempts (note, we only consider remote addresses).  If we do need to, we
    # will need to determine how many failed attempts have occurred.  This information
    # is needed with respect to two times:
    #            lookback_period_min (in secs lookback_time) - check against mark_as_brute for total login history window
    #            ip_brute_force_period_secs                  - check against max_failures_by_ip as it's a different rolling window than the mark_as_brute
    my $numfailed_byip_within_lookback_period       = 0;                                                                                                                    # lookback_period_min / lookback_time (same value in secs)
    my $numfailed_byip_within_ip_brute_force_period = 0;
    my $do_remote_ip_check                          = $self->{'conf'}{'ip_based_protection'} && $self->{'request'}{'remote_ip'} && !$self->{'request'}{'ip_is_loopback'};
    if ($do_remote_ip_check) {
        $numfailed_byip_within_lookback_period = $self->_get_failed_login_count_byip(
            $count_current_request_as_hit,
            $self->{'conf'}{'lookback_time'}
        );

        $numfailed_byip_within_ip_brute_force_period = $self->_get_failed_login_count_byip(
            $count_current_request_as_hit,
            $self->{'conf'}{'ip_brute_force_period_sec'}
        );

        $self->{'hulkd'}->debug("Failures from IP $self->{'request'}{'remote_ip'}: $numfailed_byip_within_lookback_period");
    }

    # Normally, we only want to trigger notifications the first time we detect
    # a bruteforce (within a timespan).  After that, we quietly trigger the
    # lockout.  However, this prevents us from detecting if the bruteforce is
    # *excessive*, so we first perform a check for excessive abuse.  Then we
    # can move on to the other checks.

    # Assuming remote IP checks are enabled, check for *excessive* bruteforces.
    if ( $do_remote_ip_check && $numfailed_byip_within_lookback_period >= $self->{'conf'}{'mark_as_brute'} ) {
        $self->_ip_based_brute_force_triggered(
            'excessive_failures' => '1',
            'current_failures'   => $numfailed_byip_within_lookback_period,
        );    # one day block
        return 580;    # Triggered
    }

    # To avoid a barrage of notifications, silently trigger the lockout without
    # a notification if we previously detected a bruteforce (within a timespan).
    elsif ( $self->_is_marked_as_brute($Cpanel::Config::Hulk::LOGIN_TYPE_BRUTE) ) {
        return 550;    # Already triggered, no need to notify
    }

    # Run any configured checks for a bruteforce attempt.  If one is found,
    # trigger a notification and a lockout.
    if ( $do_remote_ip_check && $numfailed_byip_within_ip_brute_force_period >= $self->{'conf'}{'max_failures_byip'} ) {
        $self->_ip_based_brute_force_triggered( 'current_failures' => $numfailed_byip_within_ip_brute_force_period );
        return 550;    # Triggered
    }

    # Trigger Username-based Protection if we have it enabled for all connections.
    my $do_username_check = $self->{'conf'}{'username_based_protection'};

    # Trigger Username-based Protection if it originated from the local machine AND we have it enabled for local connections.
    $do_username_check ||= $self->{'conf'}{'username_based_protection_local_origin'} && $self->{'request'}{'ip_is_loopback'};

    if ( $do_username_check && $self->{'request'}{'user'} eq 'root' && !$self->{'conf'}{'username_based_protection_for_root'} ) {
        $do_username_check = 0;
    }

    if ($do_username_check) {
        my $numfailed = $self->_get_failed_login_count_for_service_user($count_current_request_as_hit);
        $self->{'hulkd'}->debug("Unique login failures for Service: $self->{'request'}{'service'}, User: $self->{'request'}{'user'}: $numfailed");

        if ( $numfailed >= $self->{'conf'}{'max_failures'} ) {
            $self->_max_user_login_failures_triggered(
                'current_failures' => $numfailed,
            );
            return 550;    # Triggered
        }
    }

    return 0;              # Not Triggered
}

sub _notify_login {
    my ( $self, %OPTS ) = @_;

    $self->{'hulkd'}->debug( "_notify_login called: " . $self->_request_report($REPORT_INLINE) );
    Cpanel::Hulkd::QueuedTasks::NotifyLogin::Adder->add(
        {
            'request'     => $self->{'request'},
            'notify_opts' => \%OPTS,
        }
    );
    return Cpanel::ServerTasks::schedule_task( ['cPHulkTasks'], 2, 'notify_login' );
}

sub _notify_brute {
    my ( $self, %OPTS ) = @_;

    $self->{'hulkd'}->debug("_notify_brute called");
    delete $OPTS{'reason'};    # 'reason' has spaces in it, and throws the taskqueue arg processing off.
                               # Since we dont need that string for the queued event, just remove it.

    return Cpanel::ServerTasks::queue_task(
        ['cPHulkTasks'],
        join " ", ( 'notify_brute', Cpanel::JSON::Dump( $self->{'request'} ), Cpanel::JSON::Dump( \%OPTS ) )
    );
}

sub _login_is_new {
    my ($self) = @_;

    my $unexpired_logins_by_address = $self->unexpired_logins_by_address();
    my $good_login_lookback_time    = ( $self->{'request'}{'logintime'} - $TIME_BETWEEN_GOOD_LOGIN_NOTIFICATIONS );

    my $has_recent_good_login = 0;
    foreach my $login ( @{$unexpired_logins_by_address} ) {
        if (
            $login->{'LOGINTIME'} > $good_login_lookback_time          &&    #
            $login->{'TYPE'} == $Cpanel::Config::Hulk::LOGIN_TYPE_GOOD &&    #
            $login->{'USER'} eq $self->{'request'}{'user'}             &&    #
            $login->{'SERVICE'} eq $self->{'request'}{'service'}
        ) {
            $has_recent_good_login = 1;
            last;
        }
    }

    if ( !$has_recent_good_login ) {
        $self->_clear_request_cache();

        _send_dbwrite_cmd(
            {
                'query'            => "INSERT INTO login_track (USER,SERVICE,AUTHSERVICE,ADDRESS,LOGINTIME,TYPE,EXPTIME) VALUES(?,?,?,?,$TIMEZONESAFE_FROM_UNIXTIME,?,$TIMEZONESAFE_FROM_UNIXTIME); /*_login_is_new*/",
                'query_parameters' => [
                    $self->{'request'}{'user'},
                    $self->{'request'}{'service'},
                    $self->{'request'}{'authservice'},
                    [ $self->{'request'}{'ip_bin16'}, $self->{'request'}{'ip_version'} ],
                    $self->{'request'}{'logintime'},
                    $Cpanel::Config::Hulk::LOGIN_TYPE_GOOD,
                    ( $self->{'request'}{'logintime'} + $TIME_BETWEEN_GOOD_LOGIN_NOTIFICATIONS )
                ],
            }
        );
        return 1;
    }

    return 0;
}

sub _is_marked_as_brute {
    my ( $self, $type ) = @_;

    return 0 if !$self->{'request'}{'remote_ip'} || $self->{'request'}{'ip_is_loopback'};

    return $self->_get_last_brute_expire_time($type) ? 1 : 0;
}

sub _get_failed_login_count_for_service_user {
    my ( $self, $count_current_request ) = @_;

    my $recent_logins = $self->_logins_newer_than(
        $self->unexpired_logins_by_service_user(),
        ( time() - $self->{'conf'}{'brute_force_period_sec'} )
    );
    $self->{'hulkd'}->debug( "Number of recent logins: " . scalar(@$recent_logins) );
    return $self->_unique_login_attempts( $recent_logins, $count_current_request );
}

#
# A unique login attempt one that uses a different password then a previous attempt.
# If the login attempt was not password based it is always considered a unique attempt.
#
# This allows us to not count multiple attempts to login with the same password against
# a user.  For example, if the user changed their email password but did not update their
# android mail client, it will attempt to login over and over again with the same password.
# We only count this against them once if the cphulk client is capable of sending the hashed
# password.
#
sub _unique_login_attempts {
    my ( $self, $logins_ref, $count_current_request ) = @_;

    my %seen;

    my $count = scalar( grep { $_->{'TYPE'} == $Cpanel::Config::Hulk::LOGIN_TYPE_FAILED && ( !length $_->{'AUTHTOKEN_HASH'} || !$seen{ $_->{'USER'} }{ $_->{'AUTHTOKEN_HASH'} }++ ) } @{$logins_ref} );

    if ( $count_current_request && ( !length $self->{'request'}{'authtoken_hash'} || !length $self->{'request'}{'user'} || !$seen{ $self->{'request'}{'user'} }{ $self->{'request'}{'authtoken_hash'} } ) ) {
        $count++;
    }

    return $count;
}

sub _get_failed_login_count_byip {
    my ( $self, $count_current_request, $login_history_window_in_secs ) = @_;

    $login_history_window_in_secs ||= $self->{'conf'}{'ip_brute_force_period_sec'};

    my $recent_logins = $self->_logins_newer_than(
        $self->unexpired_logins_by_address(),
        ( time() - $self->{'conf'}{'ip_brute_force_period_sec'} )
    );
    $self->{'hulkd'}->debug( "Number of recent logins: " . scalar(@$recent_logins) );
    return $self->_unique_login_attempts( $self->_logins_newer_than( $self->unexpired_logins_by_address(), ( time() - $login_history_window_in_secs ) ), $count_current_request );
}

#Returns an arrayref: [
#   {
#       USER
#       SERVICE
#       TYPE           - one of the constants from Cpanel::Config::Hulk
#       LOGINTIME      - unixtime
#       EXPTIME        - unixtime
#       AUTHTOKEN_HASH - hash of the authtoken (password)
#   },
#   ...
#]
#
#The array is sorted on EXPTIME in descending order.
#
sub unexpired_logins_by_service_user {
    my ($self) = @_;

    $self->{'cache'}{'unexpired_logins_by_service_user'}{ $self->{'request'}{'service'} }{ $self->{'request'}{'user'} } ||= _send_dbread_cmd(
        {
            'select_func'      => 'selectall_arrayref',
            'query'            => "SELECT USER,SERVICE,TYPE,$TIMEZONESAFE_LOGINTIME,$TIMEZONESAFE_EXPTIME,AUTHTOKEN_HASH from login_track where USER=? and SERVICE=? and TYPE=? and EXPTIME > DATETIME('now','localtime') ORDER BY login_track.EXPTIME DESC /*get_unexpired_logins_by_service_user*/;",
            'extra_attr'       => { 'Slice' => {} },
            'query_parameters' => [
                $self->{'request'}{'user'},
                $self->{'request'}{'service'},
                $Cpanel::Config::Hulk::LOGIN_TYPE_FAILED
            ]
        }
    );

    return $self->{'cache'}{'unexpired_logins_by_service_user'}{ $self->{'request'}{'service'} }{ $self->{'request'}{'user'} };
}

#Returns an arrayref: [
#   {
#       USER
#       SERVICE
#       TYPE           - one of the constants from Cpanel::Config::Hulk
#       LOGINTIME      - unixtime
#       EXPTIME        - unixtime
#       AUTHTOKEN_HASH - hash of the authtoken (password)
#   },
#   ...
#]
#
#The array is sorted on EXPTIME in descending order.
#
sub unexpired_logins_by_address {
    my ($self) = @_;

    return [] if !length $self->{'request'}{'ip_bin16'};

    $self->{'cache'}{'unexpired_logins_by_address'}{ $self->{'request'}{'ip_bin16'} } ||= _send_dbread_cmd(
        {
            'select_func'      => 'selectall_arrayref',
            'query'            => "SELECT USER,SERVICE,TYPE,$TIMEZONESAFE_LOGINTIME,$TIMEZONESAFE_EXPTIME,AUTHTOKEN_HASH from login_track where EXPTIME > DATETIME('now','localtime') and ADDRESS=? ORDER BY login_track.EXPTIME DESC /*get_unexpired_logins_by_address*/;",
            'extra_attr'       => { 'Slice' => {} },
            'query_parameters' => [ [ $self->{'request'}{'ip_bin16'}, $self->{'request'}{'ip_version'} ] ],
        }
    );

    return $self->{'cache'}{'unexpired_logins_by_address'}{ $self->{'request'}{'ip_bin16'} };
}

sub _logins_newer_than {
    my ( $self, $logins_ref, $time ) = @_;

    return [ grep { $_->{'LOGINTIME'} > $time } @{$logins_ref} ];
}

sub _get_last_brute_expire_time {
    my ( $self, $type ) = @_;

    my $unexpired_logins_by_address = $self->unexpired_logins_by_address();

    return unless defined $unexpired_logins_by_address && ref $unexpired_logins_by_address eq 'ARRAY';

    foreach my $login ( @{$unexpired_logins_by_address} ) {    # Always sorted by EXPTIME DESC
        if ( $login->{'TYPE'} == $type ) {
            return $login->{'EXPTIME'};
        }
    }

    return;

}

sub _mark_brute {
    my ( $self, %OPTS ) = @_;

    $OPTS{'exptime'} ||= ( $self->{'request'}{'logintime'} + $EXCESSIVE_BRUTE_FORCE_LOCKOUT_TIME );

    $self->_block_brute(%OPTS);

    $self->_clear_request_cache();

    return _send_dbwrite_cmd(
        {
            'query'            => "INSERT INTO login_track (USER,ADDRESS,NOTES,TYPE,LOGINTIME,EXPTIME) VALUES(?,?,?,?,$TIMEZONESAFE_FROM_UNIXTIME,$TIMEZONESAFE_FROM_UNIXTIME) /*_mark_brute*/;",
            'query_parameters' => [

                # We now track the username in this instance for the case where a user forgets their password and either has it reset or resets it themselves
                # if we track the user we can clear the brute attempts for that user on password change/reset
                $self->{'request'}{'user'},
                [ $self->{'request'}{'ip_bin16'}, $self->{'request'}{'ip_version'} ],
                $OPTS{'reason'},
                $OPTS{'excessive_failures'} ? $Cpanel::Config::Hulk::LOGIN_TYPE_EXCESSIVE_BRUTE : $Cpanel::Config::Hulk::LOGIN_TYPE_BRUTE,
                $self->{'request'}{'logintime'},
                $OPTS{'exptime'}
            ],
        }
    );
}

sub _block_brute {
    my ( $self, %OPTS ) = @_;

    my $data_hr = {};

    my $command_to_run = $OPTS{'excessive_failures'} ? $self->{'conf'}{'command_to_run_on_excessive_brute_force'} : $self->{'conf'}{'command_to_run_on_brute_force'};
    if ($command_to_run) {
        my %TEMPLATE_VARS = ( %{ $self->{'request'} }, %OPTS );
        my @CMD           = map {
            my $part = $_;
            $part =~ s/\%([^\%]+)\%/$TEMPLATE_VARS{$1}/g;
            $part
        } split( m{ }, $command_to_run );

        $data_hr->{'commands'} = \@CMD;
    }

    $data_hr->{'block_with_firewall'} = $OPTS{'excessive_failures'} ? $self->{'conf'}{'block_excessive_brute_force_with_firewall'} : $self->{'conf'}{'block_brute_force_with_firewall'};
    $data_hr->{'ip_version'}          = $self->{'request'}{'ip_version'};
    $data_hr->{'remote_ip'}           = $self->{'request'}{'remote_ip'};
    $data_hr->{'exptime'}             = $OPTS{'exptime'};

    Cpanel::Hulkd::QueuedTasks::BlockBruteForce::Adder->add($data_hr);

    return Cpanel::ServerTasks::schedule_task( ['cPHulkTasks'], 1, 'block_brute_force' );
}

sub _deregister_failed_login {
    my ($self) = @_;

    # upon a successful login, the failed attempts should be removed regardless of when. It's not like they are going to keep brute forcing after they get it, and
    # it's more likely that this would only serve to block folks who forgot their password, reset it in whm/cpanel then maybe fat fingered the new one
    # Note: sudo might be sudo -i, sudo -x
    # Note: for security reasons, pam strips spaces so we will see 'sudo -i' as 'sudo-i'
    my $user = ( $self->{'request'}{'authservice'} =~ m{^sudo(?:[ -]|\z)} ? $self->{'request'}{'local_user'} : $self->{'request'}{'user'} );

    $self->{'hulkd'}->debug( "Deregistering " . $self->_request_report($REPORT_INLINE) );

    $self->_clear_request_cache();

    # Almost everything sends an IP now, however for legacy applications
    # we still need to check to see if an IP is available.
    if ( $self->{'request'}{'remote_ip'} ) {
        return _send_dbwrite_cmd(
            {
                'query'            => "DELETE FROM login_track WHERE USER=? and ADDRESS=? and TYPE=? /*_deregister_failed_login*/;",
                'query_parameters' => [
                    $user,
                    [ $self->{'request'}{'ip_bin16'}, $self->{'request'}{'ip_version'} ],
                    $Cpanel::Config::Hulk::LOGIN_TYPE_FAILED,
                ]
            }
        );
    }
    else {
        return _send_dbwrite_cmd(
            {
                'query'            => "DELETE FROM login_track WHERE USER=? and SERVICE=? and TYPE=? /*_deregister_failed_login*/;",
                'query_parameters' => [
                    $user,
                    $self->{'request'}{'service'},
                    $Cpanel::Config::Hulk::LOGIN_TYPE_FAILED,
                ]
            }
        );
    }
}

###########################################################################
#
# Method:
#   _register_failed_login
#
# Description:
#   Adds a login record to the cphulkd.login_track database
#
# Parameters:
#   exptime - The time the login record should expire
#
# Exceptions:
#   None from the function itself, however DBI may generate one
#
# Returns:
#   The status of the INSERT request
#
sub _register_failed_login {
    my ( $self, %OPTS ) = @_;

    my $exptime = $OPTS{'exptime'} || ( $self->{'request'}{'logintime'} + $self->{'conf'}{'lookback_time'} );
    my $type    = $OPTS{'type'}    || $Cpanel::Config::Hulk::LOGIN_TYPE_FAILED;

    $self->_clear_request_cache();

    return _send_dbwrite_cmd(
        {
            'query'            => "INSERT INTO login_track (ADDRESS,USER,AUTHSERVICE,SERVICE,TYPE,LOGINTIME,EXPTIME,AUTHTOKEN_HASH) VALUES(?,?,?,?,?,$TIMEZONESAFE_FROM_UNIXTIME,$TIMEZONESAFE_FROM_UNIXTIME,?) /*_register_failed_login*/;",
            'query_parameters' => [
                [ $self->{'request'}{'ip_bin16'}, $self->{'request'}{'ip_version'} ],
                $self->{'request'}{'user'},
                $self->{'request'}{'authservice'},
                $self->{'request'}{'service'},
                $type,
                $self->{'request'}{'logintime'},
                $exptime,
                $self->{'request'}{'authtoken_hash'},
            ]
        }
    );
}

sub _ip_based_brute_force_triggered {
    my ( $self, %OPTS ) = @_;

    $OPTS{'exptime'}              = $self->{'request'}{'logintime'} + ( $OPTS{'excessive_failures'} ? $EXCESSIVE_BRUTE_FORCE_LOCKOUT_TIME : $self->{'conf'}{'ip_brute_force_period_sec'} );
    $OPTS{'max_allowed_failures'} = $OPTS{'excessive_failures'} ? $self->{'conf'}{'mark_as_brute'} : $self->{'conf'}{'max_failures_byip'};
    $OPTS{'reason'}               = "IP reached maximum auth failures" . ( $OPTS{'excessive_failures'} ? " for a one day block" : '' );

    $self->_mark_brute(%OPTS);

    my $subject_line;
    my $should_notify = 0;
    if ( $OPTS{'country_is_blacklisted'} ) {
        $subject_line = 'Country Blacklist';
        $self->_send_report( %OPTS, 'type' => 'ipblock' );
    }
    elsif ( $OPTS{'ip_is_blacklisted'} ) {
        $subject_line = 'IP Blacklist';
        $self->_send_report( %OPTS, 'type' => 'ipblock' );
    }
    elsif ( $OPTS{'excessive_failures'} ) {
        $should_notify = 1;
        $subject_line  = 'Excessive';
        $self->_send_report( %OPTS, 'type' => 'ipblock' );
    }
    else {
        $should_notify = 1;
        $subject_line  = 'Large';
        $self->_send_report( %OPTS, 'type' => 'brute' );
    }

    if ( $should_notify && $self->{'conf'}{'notify_on_brute'} ) {
        $self->_notify_brute(%OPTS);
    }
    $self->_log_blocked(%OPTS);

    return 1;
}

sub _max_user_login_failures_triggered {
    my ( $self, %OPTS ) = @_;

    $OPTS{'reason'}               = 'Too many failures for this username for this authentication database.';
    $OPTS{'exptime'}              = $self->{'request'}{'logintime'} + $self->{'conf'}{'brute_force_period_sec'};
    $OPTS{'type'}                 = $Cpanel::Config::Hulk::LOGIN_TYPE_USER_SERVICE_BRUTE;
    $OPTS{'max_allowed_failures'} = $self->{'conf'}{'max_failures'};

    $self->_send_report( %OPTS, 'type' => 'max_user_login_failures' );
    $self->_log_blocked(%OPTS);

    # Only register a *single* hit if we are passed the max allowed failures
    if ( $OPTS{'current_failures'} >= $OPTS{'max_allowed_failures'} && !$self->_is_blocked_user() ) {
        $self->_register_failed_login(%OPTS);
    }

    return 1;
}

sub _is_blocked_user {
    my $self = shift;

    my $data = _send_dbread_cmd(
        {
            'select_func'      => 'selectcol_arrayref',
            'query'            => "SELECT COUNT(*) FROM login_track WHERE USER = ? AND TYPE = ?;",
            'extra_attr'       => {},
            'query_parameters' => [
                $self->{'request'}{'user'},
                $Cpanel::Config::Hulk::LOGIN_TYPE_USER_SERVICE_BRUTE,
            ]
        }
    );
    return $data->[0] if ref $data eq 'ARRAY';
    return 0;
}

sub _log_blocked {
    my ( $self, %OPTS ) = @_;
    my $reason               = $OPTS{'reason'};
    my $current_failures     = $OPTS{'current_failures'};
    my $max_allowed_failures = $OPTS{'max_allowed_failures'};
    my $exptime              = $OPTS{'exptime'};
    my $expire_time_utc      = $exptime ? gmtime($exptime)    : 'indefinite';
    my $expire_time_local    = $exptime ? localtime($exptime) : 'indefinite';

    $self->{'hulkd'}->mainlog(
        "Login Blocked:" .                                                                                     #
          ' ' .                                                                                                #
          $reason .                                                                                            #
          ' ' .                                                                                                #
          $self->_request_report($REPORT_INLINE) .                                                             #
          ( $current_failures ? " ($current_failures/$max_allowed_failures failures)"              : '' ) .    #
          ( $exptime          ? " (blocked until [$expire_time_utc UTC/$expire_time_local LOCAL])" : '' )      #
    );

    return 1;
}

sub _request_report {
    my ( $self, $report_type ) = @_;

    my @data;

    my %REQUEST_KEY_HUMAN_READABLE_NAMES = _REQUEST_KEY_HUMAN_READABLE_NAMES();

    foreach my $key ( sort keys %REQUEST_KEY_HUMAN_READABLE_NAMES ) {
        my $value = $self->{'request'}{$key};
        my $name  = $REQUEST_KEY_HUMAN_READABLE_NAMES{$key};
        $value =~ s/\s//g if length($value);
        next              if !$value;

        # The call to to_list() is a hack to avoid localization.
        push @data, { 'name' => join( ' ', $name->to_list() ), 'value' => $value };
    }

    if ( $report_type == $REPORT_INLINE ) {
        return join(
            ' ',
            map { "[$_->{'name'}]=[$_->{'value'}]" } @data
        );
    }
    else {
        return join(
            "\n",
            map { "$_->{'name'}: $_->{'value'}" } @data
        );
    }
}

sub _handle_login_ok {
    my ($self) = @_;

    # this is a special case.  This means that the pam auth was ok so we need to remove
    # the hit we put in the system when PAM_AUTHENICATE was called.
    if ( !$self->{'request'}{'ip_is_whitelisted'} && !$self->{'request'}{'country_is_whitelisted'} ) {
        $self->{'hulkd'}->debug( "Login OK (not whitelisted) " . $self->_request_report($REPORT_INLINE) );
        $self->_send_login_notification_if_needed();
        #
        # When we have a successful login, we remove all the
        # failed logins for the same user from the address
        # we successfully logged in from.
        #
        if ( $self->{'request'}{'forget_auth_failures_on_login'} && $self->_get_failed_login_count_byip( $COUNT_CURRENT_REQUEST_AS_OK, $self->{'conf'}{'lookback_time'} ) ) {
            $self->_deregister_failed_login();
        }
    }
    else {
        $self->{'hulkd'}->debug( "Login OK (whitelisted) " . $self->_request_report($REPORT_INLINE) );
    }
    return 1;
}

sub _lookup_ip_in_lists {
    my ($self) = @_;

    return 0 if !$self->{'request'}{'remote_ip'} || $self->{'request'}{'ip_is_loopback'};

    if ( $self->{'ip_list_cache'}{ $self->{'request'}{'ip_bin16'} } ) {
        $self->{'request'}{'ip_is_whitelisted'}      = $self->{'ip_list_cache'}{ $self->{'request'}{'ip_bin16'} }{'ip_is_whitelisted'};
        $self->{'request'}{'ip_is_blacklisted'}      = $self->{'ip_list_cache'}{ $self->{'request'}{'ip_bin16'} }{'ip_is_blacklisted'};
        $self->{'request'}{'country_is_whitelisted'} = $self->{'ip_list_cache'}{ $self->{'request'}{'ip_bin16'} }{'country_is_whitelisted'};
        $self->{'request'}{'country_is_blacklisted'} = $self->{'ip_list_cache'}{ $self->{'request'}{'ip_bin16'} }{'country_is_blacklisted'};

    }
    else {
        my $list_cache = Cpanel::Hulk::Cache::IpLists->new();
        my $entry      = $list_cache->fetch( $self->{'request'}{'remote_ip'} );
        if ( defined $entry ) {
            $self->{'request'}{'ip_is_whitelisted'}      = ( $entry == $Cpanel::Config::Hulk::WHITE_LIST_TYPE         ? 1 : 0 );
            $self->{'request'}{'ip_is_blacklisted'}      = ( $entry == $Cpanel::Config::Hulk::BLACK_LIST_TYPE         ? 1 : 0 );
            $self->{'request'}{'country_is_whitelisted'} = ( $entry == $Cpanel::Config::Hulk::COUNTRY_WHITE_LIST_TYPE ? 1 : 0 );
            $self->{'request'}{'country_is_blacklisted'} = ( $entry == $Cpanel::Config::Hulk::COUNTRY_BLACK_LIST_TYPE ? 1 : 0 );

        }
        else {
            my @lists = $self->_get_lists_for_address( $self->{'request'}{'ip_bin16'}, $self->{'request'}{'ip_version'} );
            $self->{'request'}{'ip_is_whitelisted'}      = ( grep { $_ == $Cpanel::Config::Hulk::WHITE_LIST_TYPE } @lists )         ? 1 : 0;
            $self->{'request'}{'ip_is_blacklisted'}      = ( grep { $_ == $Cpanel::Config::Hulk::BLACK_LIST_TYPE } @lists )         ? 1 : 0;
            $self->{'request'}{'country_is_whitelisted'} = ( grep { $_ == $Cpanel::Config::Hulk::COUNTRY_WHITE_LIST_TYPE } @lists ) ? 1 : 0;
            $self->{'request'}{'country_is_blacklisted'} = ( grep { $_ == $Cpanel::Config::Hulk::COUNTRY_BLACK_LIST_TYPE } @lists ) ? 1 : 0;

            # Handling whitelist and blacklist ips must use this match order
            # 1. IP is WHITELISTED.
            # 2. COUNTRY is WHITELISTED.
            # 3. IP is BLACKLISTED.
            # 4. COUNTRY IS BLACKLISTED.
            $list_cache->add(
                $self->{'request'}{'remote_ip'},
                  $self->{'request'}{'ip_is_whitelisted'}      ? $Cpanel::Config::Hulk::WHITE_LIST_TYPE
                : $self->{'request'}{'country_is_whitelisted'} ? $Cpanel::Config::Hulk::COUNTRY_WHITE_LIST_TYPE
                : $self->{'request'}{'ip_is_blacklisted'}      ? $Cpanel::Config::Hulk::BLACK_LIST_TYPE
                : $self->{'request'}{'country_is_blacklisted'} ? $Cpanel::Config::Hulk::COUNTRY_BLACK_LIST_TYPE
                : 0
            );
        }
        $self->{'ip_list_cache'}{ $self->{'request'}{'ip_bin16'} } = {
            'ip_is_whitelisted'      => $self->{'request'}{'ip_is_whitelisted'},
            'ip_is_blacklisted'      => $self->{'request'}{'ip_is_blacklisted'},
            'country_is_whitelisted' => $self->{'request'}{'country_is_whitelisted'},
            'country_is_blacklisted' => $self->{'request'}{'country_is_blacklisted'},

        };
    }
    return 1;
}

sub _send_login_notification_if_needed {
    my ($self) = @_;

    # Hulk tries to send notifications on pre-auth, so the auth can fail but a user
    # would still get a successful login notification. This prevents that.
    return 1 if $self->{'request'}{'op'} eq 'PRE';

    my $user = lc $self->{'request'}{'user'};
    if ( $user eq 'root' ) {
        if ( $self->_login_is_new() ) {
            if ( $self->{'conf'}{'notify_on_root_login'} ) {

                $self->{'hulkd'}->mainlog( "Notified Root Login: " . $self->_request_report($REPORT_INLINE) );

                $self->_notify_login(
                    'is_local'                            => ( $self->{'request'}{'ip_is_loopback'} ? 1 : 0 ),
                    'is_root'                             => 1,
                    'notify_on_login_from_known_netblock' => $self->{'conf'}{'notify_on_root_login_for_known_netblock'} ? 1 : 0,
                );
            }
            else {
                $self->_add_ip_known_netblocks_for_user_in_child();
            }
        }
    }
    elsif ( $user !~ tr{/}{} ) {
        my ( $user_notification_state_obj, $domain_owner );
        if ( $user !~ tr{@}{} ) {
            require Cpanel::AcctUtils::Account;
            if ( Cpanel::AcctUtils::Account::accountexists($user) ) {
                require Cpanel::ContactInfo::FlagsCache;
                $user_notification_state_obj = Cpanel::ContactInfo::FlagsCache::get_user_flagcache( 'user' => $user );
            }
        }
        else {
            my ( $virtual_user, $domain ) = split( '@', $user, 2 );
            if ( $virtual_user && $domain ) {
                require Cpanel::AcctUtils::DomainOwner::Tiny;
                if ( $domain_owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => q{} } ) ) {
                    require Cpanel::ContactInfo::FlagsCache;
                    $user_notification_state_obj = Cpanel::ContactInfo::FlagsCache::get_virtual_user_flagcache(
                        'user'         => $domain_owner,
                        'virtual_user' => $virtual_user,
                        'domain'       => $domain,
                        'service'      => $self->{'request'}{'service'},
                    );
                }
            }
        }
        if ( $user_notification_state_obj && $self->_login_is_new() ) {
            if ( $user_notification_state_obj->get_state('notify_account_login') ) {
                $self->{'hulkd'}->mainlog( "Notified User Login: " . $self->_request_report($REPORT_INLINE) );

                $self->_notify_login(
                    'is_local' => ( $self->{'request'}{'ip_is_loopback'} ? 1 : 0 ),
                    ( $domain_owner ? ( 'domain_owner' => $domain_owner ) : () ),
                    'notify_on_login_from_known_netblock' => $user_notification_state_obj->get_state('notify_account_login_for_known_netblock') ? 1 : 0,
                );
            }
            else {
                $self->_add_ip_known_netblocks_for_user_in_child();

            }
        }
    }
    return 1;
}

###########################################################################
#
# Method:
#   _add_ip_known_netblocks_for_user_in_child
#
# Description:
#    Add the current remote_ip from the request to the
#    known_netblocks table.
#
#   We define a good netblock as
#     an IP range or netblock that contains an IP address
#      from which a user successfully logged in previously.
#
# Parameters:
#   None - read from request
#     - uses remote_ip, ip_is_loopback, ip_bin16, logintime, user
#
# Returns:
#   True or False depending on the ability to create a child process
#
sub _add_ip_known_netblocks_for_user_in_child {
    my ($self) = @_;

    return if !$self->{'request'}{'remote_ip'} || $self->{'request'}{'ip_is_loopback'};

    Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser::Adder->add(
        {
            map { $_ => $self->{'request'}->{$_} }    ## no critic qw(BuiltinFunctions::ProhibitVoidMap)
              qw(
              user
              ip_bin16
              ip_version
              remote_ip
              ip_is_loopback
              )
        }
    );

    return Cpanel::ServerTasks::schedule_task( ['cPHulkTasks'], 1, 'add_known_ip_for_user', );
}

sub _send_dbread_cmd {
    my $opts_hr = shift;

    local $@;

    my $ret;

    # NB: It’s OK that errors are silenced here because they’re all
    # warn()ed anyway.
    eval { $ret = _send_dbread_cmd_or_die($opts_hr); 1 };

    return $ret;
}

sub _send_dbread_cmd_or_die {
    my $opts_hr = shift;

    # NB: Callers assume that any exceptions this function throws are
    # duplicated as warnings.

    my $hulk_client = Cpanel::Hulk->new();
    $hulk_client->db_connect() or die "Failed to connect to dbprocess socket";
    my $resp = $hulk_client->dbread($opts_hr);
    return $resp if ref $resp;
    die "Failed to execute db read command: $resp";    # Only happens if we encounter an error with the DBREAD op (timeout, etc)
}

sub _send_dbwrite_cmd {
    my $opts_hr = shift;

    my $hulk_client = Cpanel::Hulk->new();
    $hulk_client->db_connect() or return;
    $hulk_client->dbwrite($opts_hr);

    return 0;
}

sub _send_purge_old_logins_cmd {
    my $hulk_client = Cpanel::Hulk->new();
    $hulk_client->db_connect() or return;
    $hulk_client->dbpurge_old_logins();

    return;
}

sub _send_report {
    my ( $self, %OPTS ) = @_;

    return $self->{'hulkd'}->_report(
        'login_service' => $self->{'login_service'},      #
        'user'          => $self->{'request'}{'user'},    #

        'authservice' => $self->{'request'}{'authservice'},    #
        'service'     => $self->{'request'}{'service'},        #
        'remote_ip'   => $self->{'request'}{'remote_ip'},      #
        'logintime'   => $self->{'request'}{'logintime'},      #
        %OPTS,
    );

}

sub _clear_request_cache {
    my ($self) = @_;

    delete $self->{'cache'}{'unexpired_logins_by_address'}{ $self->{'request'}{'ip_bin16'} };
    delete $self->{'cache'}{'unexpired_logins_by_service_user'}{ $self->{'request'}{'service'} };

    return 1;
}

# END - These functions rely on the state of the request

#----------------------------------------------------------------------

# These functions do not rely on the state of the request

sub _send_response {
    my ( $self, $code, $response ) = @_;

    if ( $self->{'protocol'} eq 'http' ) {
        my $http_line    = '200 OK';
        my $dovecot_code = -1;                                  # HULK_PERM_LOCKED, HULK_HIT, HULK_LOCKED
        if ( $code == 200 || $code == 400 || $code == -1 ) {    # 200 = HULK_OK, 400 = HULK_ERROR, -1 = internal crash
            $dovecot_code = 0;
            if ( $code == 400 || $code == -1 ) {
                $http_line = '500 Internal Error';
            }
        }

        my $json                  = Cpanel::JSON::canonical_dump( { 'status' => $dovecot_code, 'msg' => $response } );
        my $json_length           = length $json;
        my $connection            = 'Keep-Alive';
        my $http_response_oneshot = "HTTP/1.1 $http_line\r\nConnection: $connection\r\nX-Code: $code\r\nContent-Type: application/json\r\nContent-Length: $json_length\r\n\r\n$json";

        $self->_write($http_response_oneshot);

        $self->{'hulkd'}->debug("HTTP Response: $http_response_oneshot");
    }
    else {
        $self->_write("$code $response\n");

        $self->{'hulkd'}->debug("Response: $code $response");
    }
    $self->{'connection_state'} = $CONNECTION_STATE_READ;

    return 1;
}

sub _write {
    my ( $self, $msg ) = @_;

    die "Refuse to send empty message!" if !length $msg;

    return $self->{'socket'}->syswrite($msg) || do {
        if ( !$self->{'_ignore_write_failure'} ) {
            die Cpanel::Exception::create_raw( 'IO::SocketWriteError', $! );
        }
    };
}

sub _check_connect_pass {
    my ( $self, $user, $pass ) = @_;

    my $expected_pass = Cpanel::Hulk::Key::cached_fetch_key($user);

    return ( $expected_pass && $expected_pass eq $pass ) ? 1 : 0;
}

sub _get_lists_for_address {
    my ( $self, $ip_bin16, $ip_version ) = @_;

    # If we cannot load the whitelist we need to die
    # so that we can return INTERNAL FAILURE instead of
    # continuing on and ignoring the whitelist or blacklist
    $self->{"lists_for_address_cache"}{$ip_bin16} ||= _send_dbread_cmd_or_die(
        {
            'select_func'      => 'selectcol_arrayref',
            'query'            => "SELECT TYPE from ip_lists where STARTADDRESS <= ? and ENDADDRESS >= ?; /*_get_lists_for_address*/",
            'extra_attr'       => { Slice => {} },
            'query_parameters' => [
                [ $ip_bin16, $ip_version ],
                [ $ip_bin16, $ip_version ]
            ]
        }
    );

    my $list_refs = $self->{'lists_for_address_cache'}{$ip_bin16};

    return if !ref $list_refs;
    return @{$list_refs};

}

sub purge_old_logins {
    _send_purge_old_logins_cmd();
    Cpanel::ServerTasks::queue_task( ['cPHulkTasks'], 'purge_old_logins' );

    return 1;
}

sub _lookup_ipdata_from_tty {
    my ( $self, $user, $tty ) = @_;

    # On RHEL based systems, tasks started via cron do not come into cPhulkd
    # On Ubuntu based systems, tasks started via cron come in with a tty of "cron"
    # Since this tty does not show up in the table maintained in '/var/run/utmp',
    # we are deliberately returning early here
    return if $tty eq 'cron';

    require Cpanel::IP::TTY;
    my ( $lookup_ok, $ipdata_or_error ) = Cpanel::IP::TTY::lookup_ipdata_from_tty($tty);

    if ( !$lookup_ok ) {
        $self->{'hulkd'}->errlog( $ipdata_or_error . ' ' . $self->_request_report($REPORT_INLINE) );
    }

    return $ipdata_or_error;
}

# END- These functions do not rely on the state of the request

1;
