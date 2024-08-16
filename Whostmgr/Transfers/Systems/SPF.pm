package Whostmgr::Transfers::Systems::SPF;

# cpanel - Whostmgr/Transfers/Systems/SPF.pm         Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Cpanel::SPF::Update ();

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_phase {
    return 75;
}

sub get_prereq {
    return ['ZoneFile'];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores [output,abbr,SPF,Sender Policy Framework] records and updates them for the target server.') ];
}

sub get_restricted_available {
    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my $newuser = $self->newuser();

    $self->start_action('Updating SPF Records');

    Cpanel::SPF::Update::update_spf_records( 'users' => [$newuser] );

    return 1;
}

*restricted_restore = \&unrestricted_restore;

1;
