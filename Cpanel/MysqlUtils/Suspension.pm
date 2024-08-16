package Cpanel::MysqlUtils::Suspension;

# cpanel - Cpanel/MysqlUtils/Suspension.pm              Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Suspension - Tools to suspend and unsuspend mysql users

=head1 SYNOPSIS

    use Cpanel::MysqlUtils::Suspension;

    Cpanel::MysqlUtils::Suspension::suspend_mysql_users($cpuser);

    Cpanel::MysqlUtils::Suspension::unsuspend_mysql_users($cpuser);

    my $mysql_user = $cpuser . "_" . $team_user;

    Cpanel::MysqlUtils::Suspension::suspend_mysql_users($mysql_user,$team);

    Cpanel::MysqlUtils::Suspension::unsuspend_mysql_users($mysql_user, $team);

=head2 unsuspend_mysql_users($cpuser, $team)

Unsuspend all MySQL users assoicated with the provided
cPanel user ($cpuser)

Currently we only warn on failure.  In the future this function
may be refactored to return additional status information.

If $team is provided, treat it as a mysql team user account &
unsuspend the team user mysql account.

=cut

sub unsuspend_mysql_users {
    my ( $cpuser, $team ) = @_;
    require "/usr/local/cpanel/scripts/unsuspendmysqlusers";    ## no critic qw(Modules::RequireBarewordIncludes) -- refactoring this is too large
    try {
        scripts::unsuspendmysqlusers::unsuspend( $cpuser, $team );
    }
    catch {
        warn $_;
    };
    return;
}

=head2 suspend_mysql_users($cpuser, $team)

Suspend all MySQL users assoicated with the provided
cPanel user ($cpuser)

Currently we only warn on failure.  In the future this function
may be refactored to return additional status information.

If $team is provided, treat it as a mysql team user account &
suspend the team user mysql account.

=cut

sub suspend_mysql_users {
    my ( $cpuser, $team ) = @_;
    require "/usr/local/cpanel/scripts/suspendmysqlusers";    ## no critic qw(Modules::RequireBarewordIncludes) -- refactoring this is too large
    try {
        scripts::suspendmysqlusers::suspend( $cpuser, $team );
    }
    catch {
        warn $_;
    };
    return;
}

1;
