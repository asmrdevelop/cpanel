package Cpanel::Hulk;

# cpanel - Cpanel/Hulk.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# **** DO NOT REMOVE THIS @INC unshift (or it will not be able to find Cpanel::Hulk::Constants)
# NOTE: I don't thing this is actually true any more but we'll wait for perl 5.14 binaries to be sure

use cPstrict;

BEGIN { unshift @INC, '/usr/local/cpanel'; }

# **** DO NOT REMOVE THIS @INC unshift (or it will not be able to find Cpanel::Hulk::Constants)

use Cpanel::Hulk::Key           ();
use Cpanel::Encoder::JSON       ();
use Cpanel::Config::Hulk        ();
use Cpanel::Hulk::Constants     ();
use Cpanel::Hulk::Utils         ();
use Cpanel::Socket::Constants   ();
use Cpanel::Socket::UNIX::Micro ();
use Cpanel::FHUtils::Blocking   ();
use Cpanel::FHUtils::Tiny       ();

our $READ_SIZE = 8192;

my %_CONSTANTS;

BEGIN {
    %_CONSTANTS = (

        # Invalid data provided to hulk.  LOGIN REJECTED
        HULK_INVALID => -2,

        # Trapped System failure LOGIN OK unless FAIL SECURE
        HULK_ERROR => -1,

        # Untrapped System failure LOGIN OK unless FAIL SECURE
        HULK_FAILED => 0,

        # Login is not locked out LOGIN OK
        HULK_OK => 1,

        # Login is locked out for the short brute force period LOGIN REJECTED
        HULK_LOCKED => 2,

        # Login is locked out for the exessive brute force period LOGIN REJECTED
        HULK_PERM_LOCKED => 3,

        # Login is not locked but the hit counter was incremented
        HULK_HIT => 4,
    );
}

use constant \%_CONSTANTS;

sub response_code_name ($code) {
    my %code_name = reverse %_CONSTANTS;
    return $code_name{$code} // '?';
}

*getkey       = *Cpanel::Hulk::Key::getkey;
*get_key_path = *Cpanel::Hulk::Key::get_key_path;

# Exim compatibility note:
# We should not use any modules that load any non perl default modules
# cPanelfunctions is out of the question here

sub new {
    my ($class) = @_;
    my $self = {};
    $self->{'disabled'} = Cpanel::Config::Hulk::is_enabled() ? 0 : 1;
    bless $self, $class;
    return $self;
}

sub connect {
    my ( $self, %OPTS ) = @_;
    return 0 if $self->{'disabled'};
    return $self->_connect( $Cpanel::Config::Hulk::socket, %OPTS );
}

sub db_connect {
    my ( $self, %OPTS ) = @_;
    return 0 if $self->{'disabled'};
    return $self->_connect( $Cpanel::Config::Hulk::dbsocket, %OPTS );
}

sub _connect {
    my ( $self, $socket_file, %OPTS ) = @_;

    my ( $result, $err );

    socket( $self->{'socket'}, $Cpanel::Hulk::Constants::AF_UNIX, $Cpanel::Hulk::Constants::SOCK_STREAM, 0 ) or do {
        _error_with_stack_trace("socket(AF_UNIX, SOCK_STREAM): $!\n");
        return 0;
    };

    my $usock = Cpanel::Socket::UNIX::Micro::micro_sockaddr_un($socket_file);

    if ( !CORE::connect( $self->{'socket'}, $usock ) ) {
        _error_with_stack_trace("Failed to connect to socket: $socket_file: $!");
        delete $self->{'socket'};
        return 0;
    }

    $self->{'read_buffer'} = '';

    Cpanel::FHUtils::Blocking::set_non_blocking( $self->{'socket'} );

    if ( $OPTS{'register'} ) {

        #
        #  Pipelined
        #
        my ( $proc, $key ) = @{ $OPTS{'register'} };
        $key ||= Cpanel::Hulk::Key::cached_fetch_key($proc);

        $self->_safe_send( "AUTH $proc $key\n", 2 );

        # If _safe_send has an error it will
        # close the socket. Since we do not check
        # the return value from _safe_send since
        # it does not provide error reporting
        # we call _check_socket to see if there
        # was an error
        return 0 if !$self->_check_socket();

        $result = $self->_safe_readline();
        print STDERR "Error when connecting to cphulkd: $result\n" if defined $result && index( $result, 4 ) == 0;
        if ( $result && index( $result, 2 ) == 0 && $self->{'socket'} ) {
            $result = $self->_safe_readline();
            return 1 if index( $result, 2 ) == 0;
            _error_with_stack_trace("cphulkd rejected registration attempt for $proc with: $result\n");
        }
    }
    else {
        $result = $self->_safe_readline();
        return 1                                                               if ( $result && index( $result, 2 ) == 0 && $self->{'socket'} );
        _error_with_stack_trace("Error when connecting to cphulkd: $result\n") if index( $result, 4 ) == 0;
    }

    return 0;
}

sub _error_with_stack_trace {
    my ($err) = @_;

    require Cpanel::Logger;
    my $logger = Cpanel::Logger->new( { 'alternate_logfile' => '/dev/stderr', 'open_now' => 1 } );
    $logger->warn($err);

    return 0;
}

sub _check_socket {
    my ($self) = @_;

    if ( !$self->{'socket'} ) {
        return _error_with_stack_trace('The socket is not setup in the Cpanel::Hulk object.  Do you need to call connect() first?');
    }
    elsif ( !fileno $self->{'socket'} ) {
        return _error_with_stack_trace('Cannot talk to a closed socket');
    }

    return 1;
}

sub _send_cmd {
    my ( $self, $cmd, $ignorerpy ) = @_;

    return 0     if $self->{'disabled'};
    return undef if !$self->_check_socket();

    $self->_safe_send( $cmd . "\n", 2 );

    # If _safe_send has an error it will
    # close the socket. Since we do not check
    # the return value from _safe_send since
    # it does not provide error reporting
    # we call _check_socket to see if there
    # was an error
    return undef if !$self->_check_socket();

    if ( !$ignorerpy ) {
        return $self->_safe_readline();
    }

    return 1;
}

#Returns falsey on timeout or on dropped connection.
sub _safe_send {
    my ( $self, $data, $timeout ) = @_;

    return if !$self->{'socket'};

    my $win = '';
    vec( $win, fileno( $self->{'socket'} ), 1 ) = 1;

    $self->_select_handle_EINTR( undef, $win, undef, $timeout ) or return undef;

    my $sent = send( $self->{'socket'}, $data, $Cpanel::Socket::Constants::MSG_NOSIGNAL ) or do {
        $self->_purge_socket();

        my $tolerate_yn = ( $! == $Cpanel::Hulk::Constants::EPIPE );
        $tolerate_yn ||= ( $! == $Cpanel::Hulk::Constants::ECONNRESET );

        if ( !$tolerate_yn ) {
            _error_with_stack_trace("send(): $!");
            $self->_purge_socket();
            return undef;    # _send_cmd expects us to return a false value on failure
        }
    };

    return $sent;
}

#returns undef on failure
sub _select_handle_EINTR {    ##no critic qw(RequireArgUnpacking)
    my $self = shift;

    my $timeout = $_[3];

    my $end_at = time + $timeout;

    my $nfound;

  SELECT: {
        $nfound = select( $_[0], $_[1], $_[2], ( $end_at - time ) );
        if ( $nfound == -1 ) {
            redo SELECT if $! == $Cpanel::Hulk::Constants::EINTR;
            $self->_purge_socket();
            return undef;
        }
    }

    return $nfound;
}

sub _purge_socket {
    my $self = shift;

    local $!;

    close( $self->{'socket'} ) if $self->{'socket'};

    delete $self->{'socket'};

    return 1;
}

# Returns undef on error
sub _safe_readline {
    my ( $self, $timeout ) = @_;

    $timeout = 2 unless defined $timeout;

    return undef if !$self->{'socket'};

    my $socket_mask = Cpanel::FHUtils::Tiny::to_bitmask( $self->{'socket'} );

    my $bytes_read = 0;
    while ( -1 == index( $self->{'read_buffer'}, "\n" ) ) {
        local $!;

        my $rout   = $socket_mask;
        my $nfound = $self->_select_handle_EINTR( $rout, undef, undef, $timeout );

        if ( !$nfound ) {
            if ( defined $nfound ) {
                _error_with_stack_trace("Timed out ($timeout seconds) while reading from socket.\n");
            }

            return undef;
        }

        my $delta = sysread( $self->{'socket'}, $self->{'read_buffer'}, $READ_SIZE, length $self->{'read_buffer'} );

        if ($delta) {
            $bytes_read += $delta;
        }
        else {

            #Not considered an error here; we’ll just retry.
            next if $! == $Cpanel::Hulk::Constants::EINTR;

            #One way or another, at this point we’re done.
            $self->_purge_socket();

            if ( $! && $! != $Cpanel::Hulk::Constants::ECONNRESET ) {
                _error_with_stack_trace("socket read failure: $!");
                return undef;
            }

            #We either got ECONNRESET or an empty read.
            #Don’t bother warning in this case because it probably
            #just means that the client went away.

            return undef;
        }
    }

    return substr( $self->{'read_buffer'}, 0, index( $self->{'read_buffer'}, "\n" ) + 1, '' );
}

sub register {
    my ( $self, $proc, $key ) = @_;
    return 0 if $self->{'disabled'};
    $key ||= Cpanel::Hulk::Key::cached_fetch_key($proc);
    my $result = $self->_send_cmd("AUTH $proc $key");
    return 0 if !defined $result;
    return 1 if index( $result, 2 ) == 0;
    print STDERR "cphulkd rejected registration attempt for $proc with: $result\n";
    return 0;
}

sub pre_login {
    my ( $self, %OPTS ) = @_;
    return 1 if $self->{'disabled'};
    $OPTS{'prelogin'} = 1;
    $OPTS{'status'}   = 1;
    return $self->can_login(%OPTS);
}

#XXX: This doesn’t actually return a boolean, but one of the HULK_* constant
#values defined above.
#
#Named arguments:
#   - user          (required)
#   - ip            (defaults to 127.0.0.1)
#   - status
#   - service
#   - deregister    (boolean)
#   - auth_service
#   - prelogin      (boolean)
#   - port
#
#Note that this will strip whitespace from all values before using them.
#
sub can_login {
    my ( $self, %OPTS ) = @_;
    return 1 if $self->{'disabled'};

    foreach my $opt ( keys %OPTS ) {
        $OPTS{$opt} =~ tr{  \t\r\n\f}{}d if length $OPTS{$opt};
    }
    my $user = $OPTS{'user'} || do {
        print STDERR 'null user passed to hulk.pm can_login: info: ', __PACKAGE__, "\n";
        return &HULK_INVALID;
    };
    my ( $ip, $auth_ok, $service, $quit_after, $auth_service, $authtoken, $authtoken_hash, $local_ip ) = ( ( $OPTS{'remote_ip'} || $OPTS{'ip'} ), $OPTS{'status'}, $OPTS{'service'}, $OPTS{'deregister'} ? 1 : 0, $OPTS{'auth_service'}, $OPTS{'authtoken'}, $OPTS{'authtoken_hash'}, $OPTS{'local_ip'} );
    my $logintime = time();
    my $op        = ( $OPTS{'prelogin'} ? 'PRE' : 'LOGIN' );

    if ( $op ne 'PRE' && length $authtoken && !length $authtoken_hash ) {

        # Must happen before ip is defaulted to 127.0.0.1
        $authtoken_hash = Cpanel::Hulk::Utils::hash_authtoken( $authtoken, $logintime, $user, $ip );
    }

    # If no IP address is provided, use localhost so the field is populated
    $ip ||= '127.0.0.1';

    my $remote_port = $OPTS{'remote_port'} || '';
    my $local_port  = $OPTS{'local_port'}  || '';

    my %request = (
        'action'         => $op,
        'auth_database'  => ( $service || q{} ),
        'username'       => $user,
        'remote_host'    => $ip,
        'status'         => $auth_ok,
        'login_time'     => $logintime,
        'quit_after'     => $quit_after,
        'remote_port'    => $remote_port,
        'auth_service'   => $auth_service   || q{},
        'authtoken_hash' => $authtoken_hash || q{},
        'local_host'     => $local_ip       || q{},
        'local_port'     => $local_port,
    );

    my $result = $self->_send_cmd( 'ACTION {' . join( ',', map { Cpanel::Encoder::JSON::json_encode_str($_) . ':' . Cpanel::Encoder::JSON::json_encode_str( $request{$_} ) } sort keys %request ) . '}' );
    if ($quit_after) {
        $self->_purge_socket();
    }
    if ( !defined $result ) {
        return HULK_FAILED();
    }
    elsif ( index( $result, 2 ) == 0 ) {
        return HULK_OK();
    }
    elsif ( index( $result, 58 ) == 0 ) {
        return HULK_PERM_LOCKED();
    }
    elsif ( index( $result, 55 ) == 0 ) {
        return HULK_LOCKED();
    }
    elsif ( index( $result, 50 ) == 0 ) {
        return HULK_HIT();
    }
    elsif ( index( $result, 4 ) == 0 || index( $result, -1 ) == 0 ) {

        # cphulkd will always disconnect us here
        $self->_purge_socket();

        # 400 = Database Backend Failure
        # -1 = Unknown failure
        return HULK_ERROR();
    }
    else {
        return HULK_FAILED();
    }
}

sub deregister {
    my $self = shift;

    return 1 if $self->{'disabled'};

    my $socket = $self->{'socket'};
    if ( $self->{'socket'} && Cpanel::FHUtils::Tiny::is_a( $self->{'socket'} ) ) {
        $self->_send_cmd( 'QUIT', 'ignore_reply' );

        # if mysql goes down while we have an active session, it seems _send_cmd will set the socket to undef
        close $self->{'socket'} if $self->{'socket'};
        delete $self->{'socket'};
    }

    return 1;
}

sub dbwrite {
    my ( $self, $request_hr ) = @_;

    return 1 if $self->{'disabled'};

    # TODO: See if we should stop using Cpanel::JSON::Dump() and do this
    # with Cpanel::Encoder::JSON::json_encode_str
    require Cpanel::JSON;
    $self->_send_cmd( 'DBWRITE ' . Cpanel::JSON::Dump($request_hr), 'ignore_reply' );
    $self->_purge_socket();

    return 1;
}

sub dbread {
    my ( $self, $request_hr ) = @_;
    return undef if $self->{'disabled'};

    require Cpanel::JSON;
    my $reply = $self->_send_cmd( 'DBREAD ' . Cpanel::JSON::Dump($request_hr) );
    return HULK_FAILED() if !defined $reply;

    $self->_purge_socket();

    return HULK_ERROR() if $reply !~ m/^2/;

    $reply =~ s/^200 //g;
    chomp $reply;
    return Cpanel::JSON::Load($reply);
}

sub dbpurge_old_logins {
    my $self = shift;

    return 1 if $self->{'disabled'};

    require Cpanel::JSON;
    $self->_send_cmd( 'PURGEOLDLOGINS', 'ignore_reply' );
    $self->_purge_socket();

    return 1;
}

1;
