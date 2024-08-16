package Cpanel::LinkedNode::Convert::ArchiveDirFromNode;

# cpanel - Cpanel/LinkedNode/Convert/ArchiveDirFromNode.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::ArchiveDirFromNode

=head1 SYNOPSIS

    Cpanel::LinkedNode::Convert::ArchiveDirFromNode::receive(
        archive_dir_path => '/home/cpmove-bob',
        remote_dir_path  => '/home/cpmove-bob',
        node_obj => $node,  # Cpanel::LinkedNode::Privileged::Configuration
    );

=head1 DESCRIPTION

This module copies a C<pkgacct> work directory from a linked node.

=cut

use Cpanel::LinkedNode::Convert::TarWithNode ();

use constant {
    _DEBUG => 0,
};

use constant REQ_ARGS => ( 'node_obj', 'archive_dir_path', 'remote_dir_path' );

=head1 FUNCTIONS

=head2 receive( %OPTS )

Receives an account archive from a remote node.

%OPTS are:

=over

=item * C<node_obj> - A L<Cpanel::LinkedNode::Privileged::Configuration>
instance that represents the remote node.

=item * C<archive_dir_path> - The full path to the location on the local
filesystem to copy the remote directory.

=item * C<remote_dir_path> - The full path to the C<cpmove-*> directory
that C<pkgacct> created on the remote node.

=back

=cut

sub receive (%opts) {

    my @missing = grep { !length $opts{$_} } REQ_ARGS();
    die "need: @missing" if @missing;

    my $node_obj = $opts{'node_obj'};

    Cpanel::LinkedNode::Convert::TarWithNode::receive(
        tar => {
            directory       => $opts{'archive_dir_path'},
            setuid_username => 'root',
        },
        websocket => {
            node_obj => $node_obj,
            module   => 'TarBackup',
            query    => {
                directory       => $opts{'remote_dir_path'},
                setuid_username => 'root',
            },
        },
    );

    return;
}

1;
