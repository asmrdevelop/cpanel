package Cpanel::Auth::Server;

# cpanel - Cpanel/Auth/Server.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LoadFile           ();
use Cpanel::Session::Constants ();

our $VERSION = '1.0';

my $MAX_READWRITE_TIME = 10;

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = {
        'socket'              => $OPTS{'socket'},
        'request_log_obj'     => $OPTS{'request_log_obj'},
        'error_log_obj'       => $OPTS{'error_log_obj'},
        'login_log_obj'       => $OPTS{'login_log_obj'},
        'cpconf'              => $OPTS{'cpconf'},
        'socket_caller_uid'   => $OPTS{'socket_caller_uid'},
        'socket_caller_user'  => $OPTS{'socket_caller_user'},
        'socket_caller_gid'   => $OPTS{'socket_caller_gid'},
        'socket_caller_group' => $OPTS{'socket_caller_group'},
        'socket_caller_pid'   => $OPTS{'socket_caller_pid'},
        'send_data_only'      => 0,
    };
    bless $self, $class;

    if ( !$OPTS{'cpconf'}{'root'} ) {
        die "'root' is not set in the 'cpconf' hashref";
    }

    return $self;
}

sub send_cpauthd_response {
    my ( $self, $response ) = @_;

    $response =~ s/\n/\\n/g;

    syswrite( $self->{'socket'}, $response . "\n" );
    return;
}

sub handle_cpauthd_request {
    my ($self) = @_;

    alarm($MAX_READWRITE_TIME);

    $self->{'state'} = {};

    my $handler_function;

    if ( $self->{'socket_caller_group'} eq 'mailman' ) {
        $handler_function = '_mailman_request_handler';
    }
    else {
        $self->{'error_log_obj'}->debug("cpauthd: user:group=$self->{'socket_caller_user'}:$self->{'socket_caller_group'} attempted to call cpauthd");
        $self->send_cpauthd_response("X $self->{'socket_caller_user'}:$self->{'socket_caller_group'} is not permitted to use cpauthd");
    }

    while ( my $cpauthd_request = $self->_read_cpauthd_request() ) {
        my $auth_response = $self->$handler_function($cpauthd_request);
        alarm($MAX_READWRITE_TIME);
        if ( length $auth_response->{'response'} ) {
            $self->send_cpauthd_response( $auth_response->{'response'} );
        }
    }

    alarm(0);

    return;
}

#
# Broken out for mocking
#
sub _read_request_from_socket {
    my ($self) = @_;
    my $cpauthd_request;
    {
        local $/ = "\n";
        $cpauthd_request = readline( $self->{'socket'} );
    }

    return $cpauthd_request;

}

sub _read_cpauthd_request {
    my ($self) = @_;

    $self->{'request_log_obj'}->info( "reading cpauthd request from socket at: " . __LINE__ ) if ( $self->{'cpconf'}{'log-cpauthd-requests'} );

    my $cpauthd_request = $self->_read_request_from_socket();

    $cpauthd_request =~ s/[\r\n]+$//;    #safe chmop GLOBAL

    return substr( $cpauthd_request, 0, 4096 );
}

sub _mailman_request_handler {
    my ( $self, $request_text ) = @_;
    my ( $token, $command, @data ) = split( m{ }, $request_text );

    if ( !length $token ) {
        return { 'status' => 0, 'statusmsg' => 'Invalid or missing token in cpauth request', 'error' => 1, 'response' => "Invalid or missing token in cpauth request" };
    }
    elsif ( !length $command ) {
        return { 'status' => 0, 'statusmsg' => 'Invalid or missing command in cpauth request', 'error' => 1, 'response' => "$token Invalid or missing command in cpauth request" };
    }

    my $response;
    my ( $namespace, $func ) = split( m{::}, $command, 2 );

    if ( $func eq 'RHOST' ) {
        $response = $self->_handle_mailman_rhost_request(@data);
    }
    elsif ( $func eq 'OTP' ) {
        $response = $self->_handle_mailman_otp_request(@data);
    }

    if ( $response->{'status'} ) {
        return { 'status' => $response->{'status'}, 'statusmsg' => "$command request handled", 'response' => "$token $command $response->{'data'}" };
    }
    elsif ( $response->{'status'} == 0 ) {
        return { 'status' => $response->{'status'}, 'statusmsg' => "$command request handled", 'response' => "$token $response->{'data'}" };
    }
    else {
        return { 'status' => 0, 'statusmsg' => "$token Unknown command in cpauth request: $command", 'error' => 1 };
    }
}

sub _handle_mailman_otp_request {
    my ( $self, @args ) = @_;

    my $listname = $args[0];
    my ( $user, $pass ) = split( m{_}, $args[1], 2 );

    my $response = $self->_mailman_otp( 'user' => $user, 'pass' => $pass, 'listname' => $listname );

    my $log_username = substr( $user, 0, 128 );
    $log_username =~ s{\n}{\\n};

    my $log_listname = substr( $listname, 0, 128 );
    $log_listname =~ s{\n}{\\n};

    my $remote_host = $self->{'state'}{'REMOTE_HOST'} || $self->{'state'}{'REMOTE_ADDR'} || 'unknown';
    my $entry       = sprintf(
        qq<%s - %s "MAILMAN::OTP" %s LOGIN mailman-%s: %s>,
        $remote_host,
        $log_username,
        ( $response->{'status'} ? 'DEFERRED' : 'FAILED' ),
        $log_listname,
        $response->{'data'},
    );

    $self->{'login_log_obj'}->info($entry) or warn "Failed to write entry to login_log: $entry: $!";

    return $response;
}

sub _mailman_otp {
    my ( $self, %opts ) = @_;

    my $listname = $opts{'listname'};
    my $user     = $opts{'user'};
    my $pass     = $opts{'pass'};

    return { 'status' => 0, 'data' => 'A MAILMAN::RHOST request must be made before MAILMAN::OTP' } if !$self->{'state'}{'REMOTE_ADDR'};
    return { 'status' => 0, 'data' => 'List name may not contain a slash' }                         if $listname =~ m{/};
    return { 'status' => 0, 'data' => 'User may not contain a slash' }                              if $user     =~ m{/};
    return { 'status' => 0, 'data' => 'List name contains invalid characters' }                     if $listname !~ m/^[A-Za-z0-9_\.\-]+$/;    # UI does not accept unicode characters for mailing list names (from listadmin)
    return { 'status' => 0, 'data' => 'User contains invalid characters' }                          if $user     !~ m/^[0-9A-Za-z]+$/;         # from Cpanel::CpSes::Mailman

    my $pass_file = "$Cpanel::Session::Constants::CPSES_MAILMAN_DIR/$listname\_$user";

    return { 'status' => 0, 'data' => 'The list temp user does not exist' } if !-e $pass_file;

    my $rawpass = Cpanel::LoadFile::loadfile($pass_file);

    unlink($pass_file);                                                                                                                        # no brute force, you get one try

    chomp($rawpass);

    return { 'status' => 0, 'data' => 'The list temp user does not have a password' } if !length $rawpass;

    return { 'status' => 1, 'data' => '1' } if $rawpass eq $pass;

    return { 'status' => 1, 'data' => '0' };                                                                                                   # success, but wrong pass
}

sub _handle_mailman_rhost_request {
    my ( $self, @args ) = @_;

    my ( $remote_addr, $remote_host ) = @args;

    $self->{'state'}{'REMOTE_ADDR'} = $remote_addr;
    $self->{'state'}{'REMOTE_HOST'} = $remote_host;

    return { 'status' => 1, 'data' => 'Set hosts' };
}

1;

=pod

=head1 Cpanel::Auth::Server

Cpanel::Auth::Server -- An authentication server

=head1 SYNOPSIS

  my $auth_server = Cpanel::Auth::Server->new(
      'cpconf'              => \%CPCONF,
      'socket'              => $socket,
      'socket_caller_uid'   => $socket_caller_uid,
      'socket_caller_gid'   => $socket_caller_gid,
      'socket_caller_user'  => $user,
      'socket_caller_group' => $group,
      'socket_caller_pid'   => $socket_caller_pid,
      'request_log_obj'     => $request_log_obj,
      'login_log_obj'       => $login_log_obj,
      'error_log_obj'       => $error_log_obj,
  );

  if ($err) {
      $auth_server->send_cpauthd_response($err);
  }
  else {
      $auth_server->handle_cpauthd_request();
  }

=head1 DESCRIPTION

This module provides an authentication server for checking one time
mailman password.  It is designed to be able to service other
authentication needs in the future.

=head1 PROTOCOL

The protocol is STATEFUL.

Quoting a value: strip new lines, strip spaces

Client Request
RAND NAMESPACE::COMMAND [COMMAND ARGS...]

Success Response
RAND NAMESPACE::COMMAND [RESPONSE ...]

Failure Response
RAND [RESPONSE.....]

Available calls
RAND MAILMAN::RHOST [IP] [HOST]
RAND MAILMAIL::OTP [LISTNAME] [TOKEN]

=head1 COPYRIGHT

cPanel, L.L.C.
cPanel License

=head1 AUTHORS

J. Nick Koston <nick@cpanel.net>
