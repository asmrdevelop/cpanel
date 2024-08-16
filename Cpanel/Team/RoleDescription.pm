package Cpanel::Team::RoleDescription;

# cpanel - Cpanel/Team/RoleDescription.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::DynamicUI::Loader ();
use Cpanel::Features::Load    ();
use Cpanel::Team::Constants   ();

=encoding utf-8

=head1 NAME

Cpanel::Team::RoleDescription - provide the roles to feature description

=head1 DESCRIPTION

Provides Team roles to feature list descrption mapping.

=head1 METHODS

=head2 get_role_feature_description -- retrieves team roles and its feature list descriptions.

    RETURNS: Array of Hashes with role,title of the role and the feature description array entries for the role  e.g.:
    {
        'features' => [
            'Backup',
            'Backup Wizard',
            'PHP PEAR Packages',
            'MultiPHP Manager',
            'MultiPHP INI Editor',
            'MySQL® Database Wizard',
            'MySQL® Manager',
            'MySQL® Databases',
            'Remote MySQL®',
            'Password &amp; Security',
            'PHP',
            'phpMyAdmin',
            'phpPgAdmin',
            'PostgreSQL Database Wizard',
            'PostgreSQL Databases',
            'Change Language',
            'Two-Factor Authentication'
        ],
        'id'    => 'database',
        'title' => 'Database'
    }

=cut

sub get_role_feature_description {
    my %OPTS                              = @_;
    my $dynui_data                        = Cpanel::DynamicUI::Loader::load_all_dynamicui_confs(%OPTS)->{'conf'};
    my %team_user_feature_list            = _get_team_user_feature_list();
    my @features_list_description_mapping = ();
    foreach my $role ( sort keys %team_user_feature_list ) {
        my $features_item_desc_mapping = {};
        $features_item_desc_mapping->{id}    = $role;
        $features_item_desc_mapping->{title} = $Cpanel::Team::Constants::TEAM_ROLES{$role};
        foreach my $feature_name ( @{ $team_user_feature_list{$role} } ) {
            foreach my $entry ( keys %{$dynui_data} ) {
                next if ( !exists $dynui_data->{$entry}->{feature} );
                if ( $dynui_data->{$entry}->{'feature'} =~ /$feature_name/
                    && !grep { $_ eq $dynui_data->{$entry}->{'itemdesc'} } @{ $features_item_desc_mapping->{features} } ) {
                    push @{ $features_item_desc_mapping->{features} }, $dynui_data->{$entry}->{'itemdesc'};
                }
            }
        }
        push @features_list_description_mapping, $features_item_desc_mapping;
    }

    return \@features_list_description_mapping;
}

sub _get_team_user_feature_list {
    my %team_user_feature_list = ();
    for my $role ( keys %Cpanel::Team::Constants::TEAM_ROLES ) {
        my $feature_list = Cpanel::Features::Load::load_featurelist("$Cpanel::Team::Constants::TEAM_FEATURES_DIR/$role");
        push @{ $team_user_feature_list{$role} }, grep { $feature_list->{$_} } ( sort keys %{$feature_list} );
    }
    return %team_user_feature_list;
}

1;
