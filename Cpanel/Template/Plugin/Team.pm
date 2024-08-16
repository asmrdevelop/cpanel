
# cpanel - Cpanel/Template/Plugin/Team.pm         Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Template::Plugin::Team;

use cPstrict;
use warnings;

use base 'Template::Plugin';

use Cpanel::Team::Config ();

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::Team

=head1 DESCRIPTION

Plugin that exposes various Team Manager related methods to the Template Toolkit pages.

=head1 METHODS

=head2 C<get_team_user_expire_date()>

Gets the Team User expire date.

=head3 Returns

Returns the expire date of a Team User if the Team User is set to be expired.

=cut

sub get_team_user_expire_date {

    my ( $self, $team_owner, $team_user ) = @_;

    my $expire_date_as_epoch = Cpanel::Team::Config->new($team_owner)->load()->{users}->{$team_user}->{expire_date};

    return $expire_date_as_epoch;
}

1;
