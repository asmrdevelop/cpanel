
# cpanel - Whostmgr/API/1/InitialWebsite.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::API::1::InitialWebsite;

use strict;
use warnings;
use Whostmgr::InitialWebsite         ();
use Whostmgr::InitialWebsite::Create ();
use Whostmgr::API::1::Utils          ();

use constant NEEDS_ROLE => {
    initialwebsite_create => undef,
};

=head1 NAME

Whostmgr::API::1::InitialWebsite

=head1 FUNCTIONS

=head2 initialwebsite_create

If an initial website was requested in the /var/cpanel/.create-website file, create it.

Returns:

=over

=item * requested - Boolean - True if a website was requested, false otherwise.

=item * username - String - (Only if requested is true) The username of the cPanel account
that was created.

=back

=cut

sub initialwebsite_create {
    my ( $args, $metadata ) = @_;

    if ( Whostmgr::InitialWebsite::requested() ) {
        my $info = eval { Whostmgr::InitialWebsite::Create::create(); };

        my $exception = $@;
        if ($exception) {
            Whostmgr::API::1::Utils::set_metadata_not_ok( $metadata, $exception );
            return {
                requested => 1,
            };
        }

        Whostmgr::API::1::Utils::set_metadata_ok($metadata);
        return {
            requested => 1,
            username  => $info->{username},
        };
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return {
        requested => 0,
    };
}

1;
