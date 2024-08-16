package Cpanel::DKIM::ValidityCache;

# cpanel - Cpanel/DKIM/ValidityCache.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DKIM::ValidityCache

=head1 SYNOPSIS

    $is_set = Cpanel::DKIM::ValidityCache->get('example.com');

=head1 DESCRIPTION

A simple on-disk lookup cache that intends to track whether a
given domain is set up correctly for DKIM signatures. Keys are
domain names, and values are simple booleans. All values that are
set are truthy; a falsy entry is one whose key does not exist in the
datastore.

See L<Cpanel::DKIM::ValidityCache::Write> for logic to write to this
datastore.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie ();

our $BASE_DIRECTORY = '/var/cpanel/domain_keys/validity_cache';

# Mocked in tests
sub _BASE { return $BASE_DIRECTORY; }

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 I<CLASS>->get( $DOMAIN )

Returns a boolean to indicate whether the given $DOMAIN is set
in the datastore.

=cut

sub get {
    my ( undef, $entry ) = @_;

    return Cpanel::Autodie::exists("$BASE_DIRECTORY/$entry");
}

=head2 $all_ar = I<CLASS>->get_all()

Returns a reference to an (unsorted) array of all entries, or undef
if the cache does not exist yet.

=cut

sub get_all {
    require Cpanel::FileUtils::Dir;
    return Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($BASE_DIRECTORY);
}

1;
