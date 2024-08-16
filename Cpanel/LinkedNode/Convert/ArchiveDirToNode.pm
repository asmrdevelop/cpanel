package Cpanel::LinkedNode::Convert::ArchiveDirToNode;

# cpanel - Cpanel/LinkedNode/Convert/ArchiveDirToNode.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::ArchiveDirToNode

=head1 SYNOPSIS

    Cpanel::LinkedNode::Convert::ArchiveDirToNode::send(
        archive_dir_path => '/home/cpmove-bob',
        node_obj => $node,  # Cpanel::LinkedNode::Privileged::Configuration
    );

=head1 DESCRIPTION

This module copies a C<pkgacct> work directory to a linked node.

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::Convert::TarWithNode ();
use Cpanel::LinkedNode::Worker::WHM          ();

use constant {
    _DEBUG => 0,
};

use constant REQ_ARGS => ( 'node_obj', 'archive_dir_path' );

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $remote_dir = send( %OPTS )

Sends an account archive to a remote node.

%OPTS are:

=over

=item * C<node_obj> - A L<Cpanel::LinkedNode::Privileged::Configuration>
instance that represents the remote node.

=item * C<archive_dir_path> - The full path to the local directory that
stores the C<pkgacct>-created account archive.

=item * C<tar_transform> - Optional, passed to the underlying
L<Cpanel::Streamer::TarBackup> object’s constructor (as C<transform>).

=back

The return value is the remote directory into which the archive contents
were extracted.

=cut

sub send (%opts) {
    my @missing = grep { !length $opts{$_} } REQ_ARGS();
    die "need: @missing" if @missing;

    my $node_obj = $opts{'node_obj'};

    my ( $local_dir_path, $dir_name ) = $opts{'archive_dir_path'} =~ m<\A(.+)/(.+)> or die "bad dir_path: [$opts{'archive_dir_path'}]";

    _debug("directory path: $local_dir_path");
    _debug("directory name: $dir_name");

    my $remote_dir = _get_remote_dir($node_obj) or do {
        die 'No remote dir!';
    };

    Cpanel::LinkedNode::Convert::TarWithNode::send(
        tar => {
            directory       => $local_dir_path,
            setuid_username => 'root',
            paths           => [$dir_name],
            transform       => $opts{'tar_transform'},
        },
        websocket => {
            node_obj => $node_obj,
            module   => 'TarRestore',
            query    => {
                directory       => $remote_dir,
                setuid_username => 'root',
            },
        },
    );

    return $remote_dir;
}

sub _get_remote_dir ($node_obj) {
    my $data_ar = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
        node_obj => $node_obj,
        function => 'get_homedir_roots',
    );

    return $data_ar->[0]{'path'};
}

sub _debug ($str) {
    print STDERR $str . $/ if _DEBUG;

    return;
}

1;
