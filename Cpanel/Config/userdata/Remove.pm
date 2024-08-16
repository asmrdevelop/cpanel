package Cpanel::Config::userdata::Remove;

# cpanel - Cpanel/Config/userdata/Remove.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::userdata::Constants ();

=encoding utf-8

=head1 NAME

Cpanel::Config::userdata::Remove - Tools to remove userdata (vhost data) from the system;

=head1 SYNOPSIS

    use Cpanel::Config::userdata::Remove;

    Cpanel::Config::userdata::Remove::remove_user($user);

=head2 remove_user($user)

Deletes all the userdata for a given user from the system.

Throws an exception upon error.

=cut

sub remove_user {
    my ($user) = @_;

    #This shouldn't be a problem, but if for some reason this were empty,
    #and $user were empty, then we'd have:
    #   rm -rf /
    die "Empty USERDATA_DIR global!\n" if !$Cpanel::Config::userdata::Constants::USERDATA_DIR;

    return if !length $user || index( $user, '/' ) > -1;

    my $dir = "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user";

    if ( -d $dir ) {
        require File::Path;
        File::Path::rmtree($dir);
    }

    return 1;
}

1;
