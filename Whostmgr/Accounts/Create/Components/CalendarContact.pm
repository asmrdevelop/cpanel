package Whostmgr::Accounts::Create::Components::CalendarContact;

# cpanel - Whostmgr/Accounts/Create/Components/CalendarContact.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Whostmgr::Accounts::Create::Components::CalendarContact

=head1 SYNOPSIS

    use 'Whostmgr::Accounts::Create::Components::CalendarContact';
    ...

=head1 DESCRIPTION

This module holds calendar and contact creation logic.

=cut

use cPstrict;

use Cpanel::DAV::Defaults  ();
use Cpanel::DAV::Principal ();

use parent 'Whostmgr::Accounts::Create::Components::Base';

use constant pretty_name => "Calendar and Contacts";

sub _run ( $output, $user = {} ) {

    my $principal = Cpanel::DAV::Principal->new( 'name' => $user->{'user'} );
    Cpanel::DAV::Defaults::create_calendar($principal);
    Cpanel::DAV::Defaults::create_addressbook($principal);

    return 1;
}

1;
