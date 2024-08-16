package Cpanel::Team::Constants;

# cpanel - Cpanel/Team/Constants.pm                Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Team::Constants

=head1 SYNOPSIS

    my $latest_vers               = $Cpanel::Team::Constants::LATEST_CONFIG_VERSION;
    my $max_guid_size             = $Cpanel::Team::Constants::MAX_TEAM_GUID_SIZE;
    my $max_notes_size            = $Cpanel::Team::Constants::MAX_TEAM_NOTES_SIZE;
    my $max_team_users_with_roles = $Cpanel::Team::Constants::MAX_TEAM_USERS_WITH_ROLES;
    my $team_config_dir           = $Cpanel::Team::Constants::TEAM_CONFIG_DIR;
    my $team_features_dir         = $Cpanel::Team::Constants::TEAM_FEATURES_DIR;
    my %team_role_names           = %Cpanel::Team::Constants::TEAM_ROLES;

=head1 DESCRIPTION

This module stores constants for use in the Team Manager system.

$LATEST_CONFIG_VERSION is the latest team configuration file version and is
normally stored in each team configuration file.  However, early versions
v0.1 to v0.5 were not stored anywhere and those files have to be automatically
detected by clever (or awkward) means.

$MAX_TEAM_GUID_SIZE is the maximum string length of the subaccount GUID field
in the team configuration file.

$MAX_TEAM_NOTES_SIZE is the maximum string length of the notes field in the
team configuration file.

$MAX_TEAM_USERS_WITH_ROLES is the maximum number of team-user accounts with
roles that can exist.  Includes suspended and expired team-user accounts in the
count as long as they have roles.  Can be overridden to be lower at
WHM > Edit a Package under Resources "Max Team Users with Roles".

$TEAM_CONFIG_DIR is the directory path that contains team configuration files.
There is one team configuration file per cPanel team-owner account.  That file
is named after the team-owner cPanel account username.

$TEAM_FEATURES_DIR is the directory path that contains the files that define
what features each team-user role is permitted to have.  This is where the
roles are actually defined.

%Cpanel::Team::Constants::TEAM_ROLES is a hash that contains the mapping of
internal role names to external role names for display.

$Cpanel::Team::Constants::NEEDS_MYSQL is a regex string that contains the list of
roles that need mysql.

=cut

our $LATEST_CONFIG_VERSION = 'v1.1';

our $MAX_TEAM_GUID_SIZE = 370;

our $MAX_TEAM_NOTES_SIZE = 100;

our $MAX_TEAM_USERS_WITH_ROLES = 7;

our $TEAM_CONFIG_DIR = '/var/cpanel/team';

our $TEAM_FEATURES_DIR = '/usr/local/cpanel/etc/team/features';

our %TEAM_ROLES = (
    'email'    => 'Email',
    'web'      => 'Web',
    'database' => 'Database',
    'admin'    => 'Administrator',
    'default'  => 'Default'
);

our $NEEDS_MYSQL = '(database|admin)';

1;
