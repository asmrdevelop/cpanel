package Cpanel::Server::Handler;

# cpanel - Cpanel/Server/Handler.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Alarm             ();
use Cpanel::Server::Constants ();

sub new {
    my ( $class, %OPTS ) = @_;

    foreach my $param (qw(server_obj)) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $param ] ) if !defined $OPTS{$param};
    }

    return bless { '_server_obj' => $OPTS{'server_obj'} }, $class;
}

sub get_server_obj {
    my ($self) = @_;
    return $self->{'_server_obj'} || die "_server_obj not set";
}

sub warn_in_error_log {
    my ( $self, $msg ) = @_;

    $self->get_server_obj()->get_log('error')->warn($msg);
    return undef;
}

sub read_content_length_from_socket {
    my ($self)             = @_;
    my $server_obj         = $self->get_server_obj();
    my $socket             = $server_obj->connection()->get_socket();
    my $bytes_left_to_read = int( $server_obj->request()->get_header('content-length') );
    if ( $bytes_left_to_read > $Cpanel::Server::Constants::MAX_ALLOWED_CONTENT_LENGTH_NO_UPLOAD ) {
        $server_obj->internal_error("The maximum NOed post data size is: $Cpanel::Server::Constants::MAX_ALLOWED_CONTENT_LENGTH_NO_UPLOAD");
    }
    my $content;
    my $alarm = Cpanel::Alarm->new( $Cpanel::Server::Constants::READ_CONTENT_TIMEOUT_NO_UPLOAD, sub { $server_obj->internal_error("Your request could not be processed during the allowed timeframe."); } );

    while ( $bytes_left_to_read && ( my $bytes_read = $socket->read( $content, $bytes_left_to_read, length $content ) ) ) {
        $bytes_left_to_read -= $bytes_read;
    }

    return $content;
}

# Call this from a subclass to add the process to the session’s list
# of registered processes. cpsrvd will terminate all such processes
# when the session is reaped.
#
# NB: Tested directly.
sub _register_process_in_session_if_needed {
    my ($self) = @_;

    my $server_obj = $self->get_server_obj();

    if ( my $session_id = $server_obj->get_current_session() ) {
        if ($>) {
            require Cpanel::AdminBin::Call;

            Cpanel::AdminBin::Call::call(
                'Cpanel', 'session_call', 'REGISTER_PROCESS',
                $session_id => $$,
            );
        }
        else {
            my $session_ref = $server_obj->get_current_session_ref_if_exists();
            die "Failed to get current session reference!\n" if !$session_ref;

            require Cpanel::Session::RegisteredProcesses;
            Cpanel::Session::RegisteredProcesses::add_and_save(
                $session_id,
                $session_ref,
                $$,
            );
        }
    }

    return;
}

1;
