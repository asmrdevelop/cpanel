package Cpanel::API::CacheBuster;

# cpanel - Cpanel/API/CacheBuster.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Themes::CacheBuster ();

=head1 SUBROUTINES

=over 4

=item CacheBuster::read()

read the cPanel cacheBuster id.

This is just a random integer designed to be regenerated occasionally to work w/ & around browser's
caching mechanisms.

=cut

sub read {
    my ( $args, $result ) = @_;

    # this method throw exceptions on errors which the API dispatch (the layer above this one)
    # will do the right thing(tm) with.
    my $cache_id = Cpanel::Themes::CacheBuster::get_cache_id();
    $result->data( { 'cache_id' => $cache_id } );

    return 1;
}

=item CacheBuster::update()

Set the CacheBuster ID.  This will generate and return the new cachebuster id

=cut

sub update {
    my ( $args, $result ) = @_;

    my $cache_id = Cpanel::Themes::CacheBuster::reset_cache_id();
    $result->data( { 'cache_id' => $cache_id } );

    return 1;

}

=back

=cut

my $allow_demo = { allow_demo => 1 };

our %API = (
    read   => $allow_demo,
    update => $allow_demo,
);

1;
