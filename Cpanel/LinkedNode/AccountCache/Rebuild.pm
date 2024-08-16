package Cpanel::LinkedNode::AccountCache::Rebuild;

# cpanel - Cpanel/LinkedNode/AccountCache/Rebuild.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::AccountCache::Rebuild

=head1 SYNOPSIS

    my $p = Cpanel::LinkedNode::AccountCache::Rebuild::rebuild_p( $cache_obj );

=head1 DESCRIPTION

This module contains logic to rebuild the L<Cpanel::LinkedNode::AccountCache>
cache.

=head1 SEE ALSO

L<Test::Cpanel::LinkedNode> has a convenience wrapper around this module’s
logic for synchronous use.

=cut

#----------------------------------------------------------------------

use Promise::XS ();

use Cpanel::Config::LoadCpUserFile     ();
use Cpanel::Config::Users              ();
use Cpanel::LinkedNode::Worker::GetAll ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 rebuild_p( $CACHE_OBJ )

Rebuilds the distributed-account cache and returns a promise that
resolves when the cache is saved.

$CACHE_OBJ is a L<Cpanel::LinkedNode::AccountCache> instance.

=cut

sub rebuild_p ($cache_obj) {

    my $needs_save = $cache_obj->reset();

    for my $username ( Cpanel::Config::Users::getcpusers() ) {
        my $cpuser = Cpanel::Config::LoadCpUserFile::load_or_die($username);

        if ( my @workloads = $cpuser->child_workloads() ) {
            $cache_obj->set_user_child_workloads( $username, @workloads );
            $needs_save = 1;
        }
        elsif ( my @parent_data = Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser($cpuser) ) {
            $cache_obj->set_user_parent_data( $username, map { @{$_}{ 'worker_type', 'alias' } } @parent_data );
            $needs_save = 1;
        }
    }

    return $needs_save ? $cache_obj->save_p() : Promise::XS::resolved();
}

1;
