package Cpanel::Team::Config::Limits;

# cpanel - Cpanel/Team/Config/Limits.pm            Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Autodie;
use Cpanel::Exception;
use Cpanel::Team::Constants();

=encoding utf-8

=head1 NAME

Cpanel::Team::Config::Limits

=head1 DESCRIPTION

A module to prevent bad users from exploiting MAX_TEAM_USERS_WITH_ROLES check.

cpsrvd loads this module during compile time and calls enforce_limits() for
team users before authentication. This is an additional way of preventing bad
users from exploiting and modifying the
Cpanel::Team::Constants::MAX_TEAM_USERS_WITH_ROLES variable.

The compile time load overwrites any MAX_TEAM_USERS_WITH_ROLES variable edits
by bad users.

=head1 METHODS

=over

=item * enforce_limits -- Enforces limit on team_user with roles count.

    ARGUMENTS
        team_owner    (String) -- team owner name

    RETURNS: does not return anything.

    ERRORS
        All failures are fatal.
        Fails if the team users with roles count exceeds the
        max_team_users_with_roles count.

    EXAMPLE
        Cpanel::Team::Config::Limits::enforce_limits($team_owner);

=back

=cut

sub enforce_limits {
    my $team_owner       = shift;
    my $team_config_file = "$Cpanel::Team::Constants::TEAM_CONFIG_DIR/$team_owner";
    return if !-e $team_config_file;
    Cpanel::Autodie::open( my $FH, '<', $team_config_file );
    local $/ = undef;
    my $config = <$FH>;
    close $FH;

    my $team_users_with_roles_cnt = my @all_roles = $config =~ /^[^:]+:[^:]*:([^:]+):/gm;

    require Cpanel::Team::Config;
    if ( $team_users_with_roles_cnt > Cpanel::Team::Config::max_team_users_with_roles_count($team_owner) ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The Team already has “[_1]” team users with roles. This exceeds the maximum team users with roles count of “[_2]”.', [ $team_users_with_roles_cnt, $Cpanel::Team::Constants::MAX_TEAM_USERS_WITH_ROLES ] );
    }

    return;
}

1;
