package Whostmgr::Packages::Exists;

# cpanel - Whostmgr/Packages/Exists.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::Packages::Fetch ();

=encoding utf-8

=head1 NAME

Whostmgr::Packages::Exists - Tools to determine if a package exists.

=head1 SYNOPSIS

    use Whostmgr::Packages::Exists;

    if (Whostmgr::Packages::Exists::package_exists('bob')) {
        ...
    }


=head2 package_exists($package_name)

This function determines if a package exists and is accessible to the caller.

If the logged in user is a reseller and they do not
have access to the package in question, this function
will return 0

=over 2

=item Input

=over 3

=item $package_name C<SCALAR>

    The name of the package to check for existence.

=back

=item Output

=over 3

The method returns 1 if the package exists and is accessible to the
caller; otherwise it returns 0.

=back

=back

=cut

sub package_exists {
    my ($package_name) = @_;

    my $package_list_hr = Whostmgr::Packages::Fetch::fetch_package_list( 'want' => 'exists', package => $package_name );
    if ( $package_name eq 'default' || exists $package_list_hr->{$package_name} ) {
        return 1;
    }

    return 0;
}

1;
