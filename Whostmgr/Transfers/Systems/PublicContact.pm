package Whostmgr::Transfers::Systems::PublicContact;

# cpanel - Whostmgr/Transfers/Systems/PublicContact.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::PublicContact

=head1 SYNOPSIS

N/A

=head1 DESCRIPTION

This module exists to be called from the account restore system.
It should not be invoked directly except from that framework.

It restores the user’s custom PublicContact configuration parameters
from the account archive. Its restricted and unrestricted modes
are identical.

=head1 METHODS

=cut

use Cpanel::JSON                 ();
use Cpanel::LoadFile             ();
use Cpanel::PublicContact::Write ();

use parent qw(
  Whostmgr::Transfers::Systems
);

use constant {
    get_restricted_available => 1,
};

=head2 I<OBJ>->get_summary()

POD for cplint. Don’t call this directly.

=cut

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores the account’s public contact data.') ];
}

=head2 I<OBJ>->unrestricted_restore()

POD for cplint. Don’t call this directly.

=cut

sub unrestricted_restore {
    my ($self) = @_;

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    my $file = "$extractdir/public_contact.json";

    my $json = Cpanel::LoadFile::load_if_exists($file);

    if ($json) {
        my $pcdata = Cpanel::JSON::Load($json);
        Cpanel::PublicContact::Write->set(
            $self->newuser(),
            %$pcdata,
        );
    }

    return 1;
}

*restricted_restore = \&unrestricted_restore;

1;
