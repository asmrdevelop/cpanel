package Cpanel::API::TeamRoles;

# cpanel - Cpanel/API/TeamRoles.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::AdminBin::Call ();
use Cpanel::Exception      ();
use Cpanel::Locale         ();
use Cpanel::Server::Type   ();

=encoding utf-8

=head1 NAME

Cpanel::API::TeamRoles - provide the feature description

=head1 DESCRIPTION

Provides Team roles to feature list descrption mapping.

=cut

my $non_mutating = { allow_demo => 1 };
my $mutating     = {};

our %API = (
    list_feature_descriptions => $non_mutating,
);

=head1 METHODS

=head2 list_feature_descriptions -- retrieves team roles and its feature list descriptions.

    RETURNS: Hash of role,title of the role and the feature description array entries for the role  e.g.:
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

sub list_feature_descriptions ( $args, $result ) {
    if ( !Cpanel::Server::Type::has_feature('teams') ) {
        die Cpanel::Exception::create( 'FeatureNotEnabled', 'The “[_1]” feature is not available. Ask your reseller about adding this feature.', ['Team Manager'] );
    }
    my $locale       = Cpanel::Locale->get_handle();
    my $descriptions = Cpanel::AdminBin::Call::call( 'Cpanel', 'teamroles', 'GET_TEAM_ROLE_FEATURE_DESCRIPTION' );
    $result->data($descriptions);

    return 1;
}

1;
