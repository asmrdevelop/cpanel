
# cpanel - Whostmgr/InitialWebsite.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::InitialWebsite;

use strict;
use warnings;

use constant CREATE_WEBSITE_FILE => '/var/cpanel/.create-website';
use constant CREATION_FILE       => '/var/cpanel/.create-website.done';

=head1 NAME

Whostmgr::InitialWebsite

=head1 DESCRIPTION

This module determines whether creation of an initial website when first logging in to
WHM was requested and whether it has been performed yet.

=head1 SETUP (config file)

See Whostmgr::InitialWebsite::Create for more information on the configuration.

=head1 FUNCTIONS

=head2 requested()

Returns a boolean indicating whether an initial website was requested.

=cut

sub requested {
    return -f CREATE_WEBSITE_FILE;
}

=head2 load_creation_outcome()

Loads information about the initial website creation, if any.

Returns a hash ref containing:

=over

=item * created - Boolean - Whether the creation happened. When false, it may be either
because it wasn't requested in the first place or because an error occurred. Current
usage doesn't need to know the difference.

=item * username - String - (Only when C<created> is true) The name of the cPanel user
that was created.

=back

This function may be safely used regardless of whether the creation was requested
at all, and regardless of whether it succeeded or failed. No exception should be thrown
under any of these conditions.

=cut

sub load_creation_outcome {
    my $result = {
        created => 0,
    };

    eval {
        if ( -f CREATION_FILE ) {
            require Cpanel::JSON;
            my $creation_info = Cpanel::JSON::LoadFile(CREATION_FILE);
            if ( $creation_info->{created} && $creation_info->{username} ) {
                @{$result}{qw(created username)} = @{$creation_info}{qw(created username)};
            }
        }
    };
    if ( my $exception = $@ ) {
        warn $exception;    # TODO: logger
    }

    unlink CREATION_FILE;

    return $result;
}

1;
