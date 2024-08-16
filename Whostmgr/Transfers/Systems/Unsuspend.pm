package Whostmgr::Transfers::Systems::Unsuspend;

# cpanel - Whostmgr/Transfers/Systems/Unsuspend.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use base qw(
  Whostmgr::Transfers::Systems
);

use Whostmgr::Accounts::Unsuspend::Htaccess ();

sub get_prereq {
    return ['Homedir'];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This unsuspends [asis,.htaccess] files.') ];
}

sub get_restricted_available {
    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my @domains = $self->{'_utils'}->domains();
    my $newuser = $self->{'_utils'}->local_username();

    $self->start_action( $self->_locale()->maketext( 'Unsuspending [asis,.htaccess] files for domains [list_and,_1].', \@domains ) );

    return Whostmgr::Accounts::Unsuspend::Htaccess::unsuspend_htaccess( $newuser, \@domains );
}

*restricted_restore = \&unrestricted_restore;

1;
