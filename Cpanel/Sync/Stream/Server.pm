package Cpanel::Sync::Stream::Server;

# cpanel - Cpanel/Sync/Stream/Server.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::SafeDir::MK             ();
use Cpanel::Rsync::Stream           ();
use Cpanel::Sync::Stream::Constants ();
use Cpanel::Fcntl                   ();
use Cpanel::JSON                    ();
use Cpanel::Exception               ();
use File::Spec                      ();

use base 'Cpanel::Sync::Stream::Common';

sub new {
    my ( $class, %OPTS ) = @_;

    foreach my $required (qw(socket fs_root)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$OPTS{$required};
    }

    my $self = bless {
        '_socket'          => $OPTS{'socket'},
        '_debug'           => 0,
        '_record'          => 0,
        '_file_write_flag' => Cpanel::Fcntl::or_flags(qw( O_WRONLY O_CREAT O_NOFOLLOW )),
        '_fs_root'         => File::Spec->canonpath( $OPTS{'fs_root'} ),
    }, $class;

    $self->send_server_helo();

    return $self;
}

sub handle_packet {
    my ( $self, $packet_ref ) = @_;

    if ( $packet_ref->{'type'} eq 'client_helo' ) {
        return $self->{'_remote_version'} = $packet_ref->{'version'};
    }
    elsif ( $packet_ref->{'type'} eq 'start_rsync' ) {
        return $self->respond_rsync($packet_ref);
    }
    elsif ( $packet_ref->{'disconnect'} ) { return 0; }

    return $self->send_unknown($packet_ref);
}

sub send_server_helo {
    my ($self) = @_;

    return $self->_send_packet(
        {
            'type'    => 'server_helo',
            'version' => $Cpanel::Sync::Stream::Constants::VERSION,
            'respond' => $Cpanel::Sync::Stream::Constants::NO_RESPONSE,
        }
    );
}

sub respond_rsync {
    my ( $self, $packet_ref ) = @_;

    my $relpath;
    if ( !length $packet_ref->{'direction'} || ( $packet_ref->{'direction'} ne 'upload' && $packet_ref->{'direction'} ne 'download' ) ) {
        die "The “direction” is must be “upload” or “download” for respond_rsync: " . Cpanel::JSON::Dump($packet_ref);
    }
    elsif ( $packet_ref->{'direction'} eq 'upload' ) {
        if ( !length $packet_ref->{'target_path'} ) {
            die "The “target_path” is required for respond_rsync: " . Cpanel::JSON::Dump($packet_ref);
        }
        $relpath = $self->_decode_filename( $packet_ref->{'target_path'} );
        if ( $relpath =~ m{^/} ) {
            die "The “target_path” must be a relative path when uploading to the remote cpsrvd: " . Cpanel::JSON::Dump($packet_ref);
        }
    }
    else {
        if ( !length $packet_ref->{'source_path'} ) {
            die "The “source_path” is required for respond_rsync: " . Cpanel::JSON::Dump($packet_ref);
        }
        $relpath = $self->_decode_filename( $packet_ref->{'source_path'} );
        if ( $relpath =~ m{^/} ) {
            die "The “source_path” must be a relative path when downloading from the remote cpsrvd: " . Cpanel::JSON::Dump($packet_ref);
        }
    }

    $relpath .= '/' if $relpath !~ m{/$};
    my $fullpath = File::Spec->catpath( undef, $self->_get_fs_root(), $relpath );
    Cpanel::SafeDir::MK::safemkdir( $fullpath, 0700 ) if !-e $fullpath;

    print STDERR "[chdir][fullpath][$fullpath]\n" if $self->{'_debug'};
    chdir($fullpath) or die Cpanel::Exception::create( 'IO::ChdirError', [ error => $!, path => $fullpath ] );
    Cpanel::Rsync::Stream::receive_rsync_to_cwd(
        $self->{'_socket'},
        $packet_ref->{'direction'} eq 'upload' ? $Cpanel::Rsync::Stream::IS_RECEIVER : $Cpanel::Rsync::Stream::IS_SENDER,
        $packet_ref->{'rsync_command'}
    );

    return 0;    # we closed the socket so we have to disconnect
}

1;
