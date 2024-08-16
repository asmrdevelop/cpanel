package Cpanel::Sync::Stream;

# cpanel - Cpanel/Sync/Stream.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Exception               ();
use Cpanel::JSON                    ();
use Cpanel::Carp                    ();
use Cpanel::LoadModule              ();
use Cpanel::Sync::Stream::Constants ();
use File::Spec                      ();
use MIME::Base64                    ();
use Errno                           ();

use Try::Tiny;

sub receive_and_process_one_packet {
    my ( $self, $message ) = @_;
    my $packet = $self->_read_one_packet() or return;
    if ( $self->{'_debug'} ) {
        Cpanel::LoadModule::load_perl_module('Data::Dumper');
        print STDERR "[$message][$packet->{'type'}]: " . Data::Dumper::Dumper($packet);
    }
    $self->handle_packet($packet) or return;
    return 1;
}

sub _read_one_packet {
    my ($self) = @_;

    my $packet_length;
    $self->_read_exactly( \$packet_length, $Cpanel::Sync::Stream::Constants::HEADER_SIZE );
    if ( $packet_length <= 0 ) {
        die "Expected packet length, got $packet_length";
    }

    my $json;
    $self->_read_exactly( \$json, $packet_length );

    print STDERR "[$$][recv][[$packet_length$json]]\n" if $self->{'_debug'};
    return Cpanel::JSON::Load($json);
}

sub _read_exactly {
    my ( $self, $buffer_ref, $left ) = @_;

    $$buffer_ref = '';
    my $total_bytes = $left;
    my $bytes_read;
    while ( $bytes_read = read( $self->{'_socket'}, $$buffer_ref, $left, length $$buffer_ref ) ) {
        $left -= $bytes_read;
        last if !$left;
    }
    die Cpanel::Carp::safe_longmess("Failed to read “$left/$total_bytes” bytes.") if $left;
    return $left;
}

sub _write_to_socket {
    my ( $self, $buffer_ref ) = @_;

    my ( $total_written, $written );
    local $!;

    # keep trying to write as the socket may only accept some at a time (SSL)
    while ( length $$buffer_ref ) {

        $total_written += ( $written = syswrite( $self->{'_socket'}, $$buffer_ref ) );
        if ( $written == -1 || $! ) {
            die Cpanel::Exception::create( 'IO::WriteError', [ error => $!, length => length $$buffer_ref ] );
        }
        return $total_written if !$written || !length $$buffer_ref;
        substr( $$buffer_ref, 0, $written, '' );
    }
    return $total_written;
}

sub _send_packet {
    my ( $self, $packet_ref ) = @_;

    $packet_ref->{'record'} = ++$self->{'_record'};
    my $json   = Cpanel::JSON::Dump($packet_ref);
    my $buffer = sprintf( "%${Cpanel::Sync::Stream::Constants::HEADER_SIZE}d", length $json ) . $json;
    print STDERR "[$$][send][[$buffer]]\n" if $self->{'_debug'};
    return $self->_write_to_socket( \$buffer );
}

sub _get_fs_root {
    my ($self) = @_;
    die "_fs_root unset" if !$self->{'_fs_root'};
    return $self->{'_fs_root'};
}

sub _decode_filename {
    my ( $self, $filename ) = @_;
    return File::Spec->canonpath( MIME::Base64::decode_base64($filename) ) if $self->{'_remote_version'} < 2;
    return File::Spec->canonpath($filename);
}

sub _encode_filename {
    my ( $self, $filename ) = @_;
    return MIME::Base64::encode_base64($filename) if !$self->{'_remote_version'} || $self->{'_remote_version'} < 2;
    return $filename;

}

1;
