package Cpanel::LinkedNode::Convert::ToDistributed::Mail::SendHomedirMail;

# cpanel - Cpanel/LinkedNode/Convert/ToDistributed/Mail/SendHomedirMail.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::ToDistributed::Mail::SendHomedirMail

=head1 SYNOPSIS

    Cpanel::LinkedNode::Convert::ToDistributed::Mail::SendHomedirMail::send(
        username => 'bob',
        node_obj => $node,  # Cpanel::LinkedNode::Privileged::Configuration
    );

=head1 DESCRIPTION

This module implements the part of conversion to distributed-mail
that copies mail-related files from the user’s home directory.

This isn’t for use during account restorations; for the logic to use
in that context, see
L<Cpanel::LinkedNode::Convert::ToDistributed::Mail::SendHomedir>.

=cut

#----------------------------------------------------------------------

use Cpanel::AccessIds::ReducedPrivileges         ();
use Cpanel::Autodie                              ();
use Cpanel::PwCache                              ();
use Cpanel::LinkedNode::Convert::Mail::Constants ();
use Cpanel::LinkedNode::Convert::TarWithNode     ();
use Cpanel::LinkedNode::Worker::Utils            ();

use constant REQ_ARGS => ( 'node_obj', 'username' );

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 send( %OPTS )

Sends the mail-related homedir pieces. %OPTS are:

=over

=item * C<username>

=item * C<node_obj> - a L<Cpanel::LinkedNode::Privileged::Configuration>
instance

=back

=cut

sub send (%opts) {
    my @missing = grep { !length $opts{$_} } REQ_ARGS();
    die "need: @missing" if @missing;

    my $homedir = Cpanel::PwCache::gethomedir( $opts{'username'} );

    my $remote_homedir = Cpanel::LinkedNode::Worker::Utils::get_remote_homedir( @opts{ 'node_obj', 'username' } );

    my @paths = do {
        my $privs = Cpanel::AccessIds::ReducedPrivileges->new( $opts{'username'} );

        grep { Cpanel::Autodie::exists("$homedir/$_") } Cpanel::LinkedNode::Convert::Mail::Constants::HOMEDIR_PATHS();
    };

    Cpanel::LinkedNode::Convert::TarWithNode::send(
        tar => {
            directory       => $homedir,
            setuid_username => $opts{'username'},
            paths           => \@paths,
        },
        websocket => {
            node_obj => $opts{'node_obj'},
            module   => 'TarRestore',
            query    => {
                setuid_username => $opts{'username'},
                directory       => $remote_homedir,
            },
        },
    );

    return;
}

1;
