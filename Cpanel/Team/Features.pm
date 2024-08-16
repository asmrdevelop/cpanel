package Cpanel::Team::Features;

# cpanel - Cpanel/Team/Features.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Features::Load  ();
use Cpanel::Team::Constants ();
use Cpanel::Features        ();
use Cpanel::Team::Config    ();

=encoding utf-8

=head1 NAME

Cpanel::Team::Features

=head1 DESCRIPTION

Provides Team User Roles to feature list mapping.

=head1 METHODS

=over

=item * load_team_feature_list -- Provides Team User Roles to feature list mapping.

    RETURNS: User feature list hash as follows.

    $VAR1 = {
        'lists'                => 1,
        'modsecurity'          => 0,
        'wp-toolkit-deluxe'    => 0,
        'clamavconnector_scan' => 0,
        'ea-php74'             => 0,
        'hotlink'              => 0,
        'emailauth'            => 1,
        'wp-toolkit'           => 0,
        'statselect'           => 0,
        'apitokens'            => 0,
        'awstats'              => 0,
        'sslinstall'           => 0,
        'version_control'      => 0,
        'filemanager'          => 0,
        'ssh'                  => 0,
        'nettools'             => 0,
        'errpgs'               => 0,
        'csvimport'            => 1,
        'bandwidth'            => 0,
        'ror'                  => 0,
        'password'             => 1
    };

    EXAMPLE
        my $TEAM_USER_FEATURES = Cpanel::Team::Features::load_team_feature_list( $TEAM_OWNER_FEATURES, $feature_list_ref->{'file'} );

=cut

sub load_team_feature_list {
    my ( $cPuser_feature_list, $feature_list_ref_file ) = @_;
    my $team_user_featurelist = _get_team_user_features();
    _sync_team_user_with_owner_list( $cPuser_feature_list, $team_user_featurelist );
    _remove_restricted_privileges($team_user_featurelist);
    _load_team_user_featurelist_with_missing_features($team_user_featurelist);

    return $team_user_featurelist;
}

sub _get_team_user_features {
    my @team_roles                    = _get_roles();
    my $roles_to_feature_list_mapping = _get_role_to_feature_list_mapping( \@team_roles );

    return $roles_to_feature_list_mapping;
}

sub _get_role_to_feature_list_mapping {
    my $roles = shift;
    my $role_list_mapping;
    my %combined_role_list_mapping;
    my @enabled_list;
    foreach my $role (@$roles) {
        next if ( !-e "$Cpanel::Team::Constants::TEAM_FEATURES_DIR/$role" );    # Should expand further to die when we don't have roles to list mapping on server
        $role_list_mapping = Cpanel::Features::Load::load_featurelist("$Cpanel::Team::Constants::TEAM_FEATURES_DIR/$role");
        push @enabled_list, grep { $role_list_mapping->{$_} } ( keys %{$role_list_mapping} );
        push @enabled_list, Cpanel::Features::load_addon_feature_names() if $role eq 'admin';
    }
    %combined_role_list_mapping = map { $_ => 1 } @enabled_list;
    return \%combined_role_list_mapping;
}

sub _sync_team_user_with_owner_list {
    my ( $owner_feature_list, $team_user_feature_list ) = @_;
    foreach my $feature ( keys %{$team_user_feature_list} ) {
        if ( exists $owner_feature_list->{$feature} && !$owner_feature_list->{$feature} ) {
            $team_user_feature_list->{$feature} = 0;
        }
    }

    return;
}

sub _remove_restricted_privileges {
    my ($team_user_features_list) = @_;
    my @restricted_feature_list = ( 'team_manager', 'user_manager' );
    foreach my $list (@restricted_feature_list) {
        $team_user_features_list->{$list} = 0;
    }
    return;
}

sub _load_team_user_featurelist_with_missing_features {
    my ($team_user_features_list) = @_;
    my @complete_feature_list = ( Cpanel::Features::load_addon_feature_names(), Cpanel::Features::load_feature_names() );
    foreach my $feature (@complete_feature_list) {
        $team_user_features_list->{$feature} = 0 if !exists $team_user_features_list->{$feature};
    }
    return;
}

=item * get_max_team_feature_mtime -- Provides max modified timestamp for Team Feature file.

    RETURNS: max mtime for team_user; 0 otherwise.

    EXAMPLE
        my $max_team_feature_mtime = Cpanel::Team::Features::get_max_team_feature_mtime( $ENV{'TEAM_OWNER'}, $ENV{'TEAM_USER'} );

=back

=cut

sub get_max_team_feature_mtime {
    my ( $team_owner, $team_user ) = @_;
    my $team_feature_mtime = my $max_team_feature_mtime = 0;
    my @team_roles         = _get_roles();
    foreach my $role (@team_roles) {
        next if ( !-e "$Cpanel::Team::Constants::TEAM_FEATURES_DIR/$role" );    # Should expand further to die when we don't have roles to list mapping on server
        $team_feature_mtime     = ( stat("$Cpanel::Team::Constants::TEAM_FEATURES_DIR/$role") )[9];
        $max_team_feature_mtime = $max_team_feature_mtime > $team_feature_mtime ? $max_team_feature_mtime : $team_feature_mtime;
    }
    return $max_team_feature_mtime;
}

sub _get_roles {
    my @team_roles;
    if ( $ENV{'TEAM_USER_ROLES'} ) {
        @team_roles = split /,/, $ENV{'TEAM_USER_ROLES'};
    }
    else {
        my $team = Cpanel::Team::Config->new( $ENV{'TEAM_OWNER'} );
        @team_roles = @{ $team->get_team_user_roles( $ENV{'TEAM_USER'} ) };
    }
    push @team_roles, 'default';    # All roles have default feature lists
    return @team_roles;
}

1;
