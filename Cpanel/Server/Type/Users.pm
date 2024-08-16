package Cpanel::Server::Type::Users;

# cpanel - Cpanel/Server/Type/Users.pm                      Copyright 2022 cPanel L.L.C
#                                                            All rights reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Server::Type                           ();
use Cpanel::Config::LoadUserDomains::Count::Active ();

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Users - Information about licensed active users

=head1 FUNCTIONS

=head2 max_users_exceeded()

If the number of active users (not suspended) exceeds the number
of licensed users this function returns 1, otherwise it returns 0.

=cut

sub max_users_exceeded {

    my $current_users = Cpanel::Config::LoadUserDomains::Count::Active::count_active_trueuserdomains() // 0;
    my $max_users     = Cpanel::Server::Type::get_max_users()                                          // 0;

    # max_users of 0 is unlimited
    return $max_users && $current_users > $max_users ? 1 : 0;
}
1;
