package Cpanel::LinkedNode::Convert::FromDistributed::Mail::RetrieveHomedirMail;

# cpanel - Cpanel/LinkedNode/Convert/FromDistributed/Mail/RetrieveHomedirMail.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::FromDistributed::Mail::RetrieveHomedirMail

=head1 SYNOPSIS

    Cpanel::LinkedNode::Convert::FromDistributed::Mail::RetrieveHomedirMail::send(
        username => 'bob',
        node_obj => $node,  # Cpanel::LinkedNode::Privileged::Configuration
    );

=head1 DESCRIPTION

This module implements the part of conversion to de-distribute mail
that copies mail-related files from the user’s home directory.

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::Convert::Mail::Constants ();
use Cpanel::LinkedNode::Convert::TarWithNode     ();
use Cpanel::LinkedNode::Worker::Utils            ();
use Cpanel::PwCache                              ();

use constant REQ_ARGS => ( 'node_obj', 'username' );

=head1 FUNCTIONS

=head2 retrieve( %OPTS )

Retrieves the mail-related homedir pieces. %OPTS are:

=over

=item * C<username>

=item * C<node_obj> - a L<Cpanel::LinkedNode::Privileged::Configuration>
instance

=back

=cut

sub retrieve (%opts) {
    my @missing = grep { !length $opts{$_} } REQ_ARGS();
    die "need: @missing" if @missing;

    my $homedir = Cpanel::PwCache::gethomedir( $opts{'username'} );

    my $remote_homedir = Cpanel::LinkedNode::Worker::Utils::get_remote_homedir( @opts{ 'node_obj', 'username' } );

    my @paths = Cpanel::LinkedNode::Convert::Mail::Constants::HOMEDIR_PATHS();

    Cpanel::LinkedNode::Convert::TarWithNode::receive(
        tar => {
            directory       => $homedir,
            setuid_username => $opts{'username'}
        },
        websocket => {
            node_obj => $opts{'node_obj'},
            module   => 'TarBackup',
            query    => {
                setuid_username => $opts{'username'},
                directory       => $remote_homedir,
                paths           => \@paths,
            },
        },
    );

    return;
}

1;
