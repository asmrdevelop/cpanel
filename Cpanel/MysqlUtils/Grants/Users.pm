package Cpanel::MysqlUtils::Grants::Users;

# cpanel - Cpanel/MysqlUtils/Grants/Users.pm               Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub get_all_hosts_for_users {
    my ( $dbh, $users ) = @_;

    my $user_list = join( ',', map { $dbh->quote($_) } @{$users} );

    my $hosts_ar = $dbh->selectall_arrayref("SELECT user, host FROM mysql.user WHERE user IN ($user_list);");

    my %user_hosts_map;
    if ( $hosts_ar && @{$hosts_ar} ) {
        foreach my $user_host ( @{$hosts_ar} ) {
            my ( $user, $host ) = @{$user_host};

            push @{ $user_hosts_map{$user} }, $host;
        }
    }

    return \%user_hosts_map;
}

#Calls DROP USER for all hosts where the user has access.
sub drop_user_in_mysql {
    my ( $dbh, $user ) = @_;

    my $user_hosts_map = get_all_hosts_for_users( $dbh, [$user] );

    for my $host ( @{ $user_hosts_map->{$user} } ) {
        $dbh->do( 'DROP USER ?@?', undef, $user, $host );
    }

    return 1;
}

1;
