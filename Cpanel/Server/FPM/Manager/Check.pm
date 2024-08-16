package Cpanel::Server::FPM::Manager::Check;

# cpanel - Cpanel/Server/FPM/Manager/Check.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception            ();
use IO::Socket::UNIX             ();
use IO::Select                   ();
use Cpanel::Server::FPM::Manager ();
use Cpanel::FileUtils::Dir       ();

our $MAX_READ_ATTEMPTS  = 100;
our $FALLBACK_TEST_USER = 'cpanelphpmyadmin';

# This is obtained by the following multi-command concatenation:
# Net::FastCGI::Protocol::build_record(
#      FCGI_BEGIN_REQUEST, 2, Net::FastCGI::Protocol::build_begin_request_body( FCGI_RESPONDER, FCGI_KEEP_CONN )
# ) .
# Net::FastCGI::Protocol::build_record(
#      FCGI_PARAMS, 2, Cpanel::CPAN::Net::FastCGI::Fast::build_params( { 'REQUEST_METHOD' => 'GET' } )
# ) .
# Net::FastCGI::Protocol::build_record( FCGI_PARAMS, 2, '' ) .
# Net::FastCGI::Protocol::build_record( FCGI_STDIN, 2, '' )
my $FCGI_SIMPLE_REQUEST =
  "\x{0001}\x{0001}\x{0000}\x{0002}\x{0000}\b\x{0000}\x{0000}\x{0000}\x{0001}\x{0001}\x{0000}\x{0000}\x{0000}\x{0000}\x{0000}\x{0001}\x{0004}\x{0000}\x{0002}\x{0000}\x{0013}\x{0005}\x{0000}\x{000e}\x{0003}REQUEST_METHODGET\x{0000}\x{0000}\x{0000}\x{0000}\x{0000}\x{0001}\x{0004}\x{0000}\x{0002}\x{0000}\x{0000}\x{0000}\x{0000}\x{0001}\x{0005}\x{0000}\x{0002}\x{0000}\x{0000}\x{0000}\x{0000}";

sub new {
    my ($class) = @_;

    return bless {}, $class;
}

sub service {
    return 'cpanel_php_fpm';
}

sub _find_user_to_check {
    my $active_users_ref = Cpanel::Server::FPM::Manager::get_all_active_users();

    # Try to check a user that does not have any active
    # connections in order to ensure that the parent process is
    # not in a wedged state and unable to create a child since
    # the we end up connecting to the active child if one
    # already exists.

    # Case ZC-4937
    # Update on this code, we used to pick either cpanelphpmyadmin or
    # cpanelroundcube, well most of the time roundcube does NOT use it's
    # own pool so it would randomly fail.  So we are now going to find out
    # what has been configured and work with it.

    my $user_to_check;
    if ( !-d '/var/cpanel/php-fpm.d' ) {
        my $contents  = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists('/var/cpanel/php-fpm.d');
        my @fpm_users = map { substr( $_, -5, 5, "" ) eq ".conf" ? $_ : () } @{$contents};                ## no critic(ControlStructures::ProhibitMutatingListFunctions) - its ok to fiddle w/ $_ in a short map()
        $user_to_check = ( grep { !$active_users_ref->{$_} } sort @fpm_users )[0];
    }

    # If all users have active processes we fallback to
    # cpanelphpmyadmin
    $user_to_check ||= $FALLBACK_TEST_USER;

    return $user_to_check;
}

sub check {
    my ($self) = @_;

    my $user_to_check = _find_user_to_check();

    return $self->_dummy_request_to_fpm_socket_or_die(
        'socket' => $self->_connect_to_fpm_socket_or_die( 'user' => $user_to_check ),
        'user'   => $user_to_check,
    );
}

sub _dummy_request_to_fpm_socket_or_die {
    my ( $self, %OPTS ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'user' ] )   if !$OPTS{'user'};
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'socket' ] ) if !$OPTS{'socket'};

    my $socket = $OPTS{'socket'};
    my $user   = $OPTS{'user'};

    my $buffer;
    local $@;
    eval {
        $socket->blocking(0);
        $self->_send_basic_fastcgi_request($socket);
        my $attempts = 0;
        my $select   = IO::Select->new($socket);
        while ( ++$attempts < $MAX_READ_ATTEMPTS ) {    # 10 second response timeout (0.1s/read attempt)
            my $sysread_result = sysread( $socket, $buffer, 1 );
            last if ( $sysread_result && $sysread_result == 1 );
            $select->can_read(0.1);
        }
    };
    if ( $@ || !length $buffer ) {
        die Cpanel::Exception::create(
            'Services::BadResponse',
            [
                'service'  => $self->service(),
                'longmess' => undef,
                'socket'   => $self->_get_fpm_socket_path($user),
                'error'    => ( $@ || 'The system failed to read a response from the service' )
            ]
        )->to_string()
          . "\n";
    }
    return 1;
}

sub _get_fpm_socket_path {
    my ( $self, $test_user ) = @_;

    die "_get_fpm_socket_path requires a test user" if !$test_user;

    return $Cpanel::ConfigFiles::FPM_ROOT . '/' . $test_user . '/sock';
}

sub _connect_to_fpm_socket_or_die {
    my ( $self, %OPTS ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'user' ] ) if !$OPTS{'user'};

    my $socket_path = $self->_get_fpm_socket_path( $OPTS{'user'} );
    my $socket;
    {
        local $@;
        $socket = eval { IO::Socket::UNIX->new($socket_path) };
        if ( $@ || !$socket ) {
            die Cpanel::Exception::create(
                'Service::IsDown',
                [
                    'service'  => $self->service(),
                    'longmess' => undef,
                    'socket'   => $socket_path,
                    'error'    => ( $@ || 'Failed to connect to socket: ' . $self->_get_fpm_socket_path( $OPTS{'user'} ) ),
                ]
            )->to_string()
              . "\n";
        }
    };
    return $socket;
}

sub _send_basic_fastcgi_request {
    my ( $self, $socket ) = @_;
    return syswrite( $socket, $FCGI_SIMPLE_REQUEST );

}

1;
