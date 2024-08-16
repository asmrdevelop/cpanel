#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/teamroles.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::teamroles;

use cPstrict;

use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Exception              ();
use Cpanel::Team::RoleDescription  ();

use parent qw( Cpanel::Admin::Base );

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::teamroles

=head1 SYNOPSIS

  use Cpanel::AdminBin::Call ();

  Cpanel::AdminBin::Call::call ( "Cpanel", "teamroles", "GET_TEAM_ROLE_FEATURE_DESCRIPTION", {} );

=head1 DESCRIPTION

This admin bin is used to return team roles to feature description as the adminbin user.

=cut

sub _actions {
    return qw(GET_TEAM_ROLE_FEATURE_DESCRIPTION);
}

use constant _allowed_parents => (
    __PACKAGE__->SUPER::_allowed_parents(),
);

=head1 METHODS

=head2 LOG(JSON, API_TYPE)

Logs a serialized JSON structure to the analytics log file.

=head3 ARGUMENTS

=over

=item JSON - string

JSON data blob stored as string. Must not include any newline characters.

=item API_TYPE - restricted string

The API type (uapi,...)

=back

=head3 RETURNS

The success status of the write, either 1 or undef.

=cut

sub GET_TEAM_ROLE_FEATURE_DESCRIPTION {
    my ( $self, $call ) = @_;
    my $team_owner = $self->get_caller_username();
    my $homedir    = $self->get_cpuser_homedir();
    my $theme      = Cpanel::Config::LoadCpUserFile::load($team_owner)->{'RS'};
    my %OPTS       = (
        'user'         => $team_owner,
        'theme'        => $theme,
        'homedir'      => $homedir,
        'ownerhomedir' => $homedir
    );

    my @role_feature_description = eval { Cpanel::Team::RoleDescription::get_role_feature_description(%OPTS) };
    die Cpanel::Exception::create( 'AdminError', [ message => Cpanel::Exception::get_string_no_id($@) ] ) if $@;
    return \@role_feature_description;
}

1;
