package Cpanel::Sync::Stream::UnguardedClient;

# cpanel - Cpanel/Sync/Stream/UnguardedClient.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use File::Spec                      ();
use Cpanel::Fcntl                   ();
use Cpanel::Sync::Stream::Constants ();
use Cpanel::Exception               ();

use base 'Cpanel::Sync::Stream::Common';

sub new {
    my ( $class, %OPTS ) = @_;

    foreach my $required (qw(client fs_root)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$OPTS{$required};
    }

    my $self = bless {
        '_client'         => $OPTS{'client'},
        '_debug'          => 0,
        '_record'         => 0,
        '_file_read_flag' => Cpanel::Fcntl::or_flags(qw( O_RDONLY O_NOFOLLOW )),
        '_fs_root'        => File::Spec->canonpath( $OPTS{'fs_root'} ),
    }, $class;

    if ( my $socket = $self->{'_client'}->get_socket() ) {
        $self->{'_socket'} = $socket;
        $self->post_connect_helo();
    }

    return $self;
}

sub send_start_rsync {
    my ( $self, $source_path, $target_path, $direction, $remote_rsync_command ) = @_;

    if ( $direction eq 'download' && $source_path =~ m{^/} ) {
        die "The “source_path” must be a relative path when the direction is “download”";
    }
    elsif ( $direction eq 'upload' && $target_path =~ m{^/} ) {
        die "The “target_path” must be a relative path when the direction is “upload”";
    }

    return $self->_send_packet(
        {
            'type'          => 'start_rsync',
            'source_path'   => $self->_encode_filename($source_path),
            'target_path'   => $self->_encode_filename($target_path),
            'direction'     => $direction,
            'rsync_command' => $remote_rsync_command,
            'disconnect'    => 1,
        },
    );
}

sub send_client_helo {
    my ($self) = @_;

    return $self->_send_packet(
        {
            'type'    => 'client_helo',
            'version' => $Cpanel::Sync::Stream::Constants::VERSION,
            'respond' => $Cpanel::Sync::Stream::Constants::NO_RESPONSE,
        }
    );
}

### END

sub handle_packet {
    my ( $self, $packet_ref ) = @_;

    if    ( $packet_ref->{'type'} eq 'server_helo' ) { return $self->{'_remote_version'} = $packet_ref->{'version'} }
    elsif ( $packet_ref->{'disconnect'} )            { return 0; }

    return $self->send_unknown($packet_ref);
}

sub post_connect_helo {
    my ($self) = @_;
    $self->send_client_helo();
    return $self->receive_and_process_one_packet();

}

1;
