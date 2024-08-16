package Whostmgr::Accounts::Create::Components;

# cpanel - Whostmgr/Accounts/Create/Components.pm  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Whostmgr::Accounts::Create

=head1 SYNOPSIS

    use Whostmgr::Accounts::Create::Components ();
    my $output = '';
    my @components2run = Whostmgr::Accounts::Create::Components::get();
    $_->run( \$output, $user ) or $_->rollback( \$output, $user ) for @components2run;

=head1 DESCRIPTION

This module is here to break up Whostmgr::Accounts::Create::_wwwacct into smaller
more testable components whilst preserving the ordering of the previous
subroutine by having the getter return an ordered list of objects to
execute subs for the given bit of a cPanel account you want to create.

I leave the similarity of this design to Remove's cleanup modules and the
implications of such as "an exercise for the reader" - TAB

=cut

use cPstrict;

# Order here is not important.
use Whostmgr::Accounts::Create::Components::CalendarContact ();    # PPI NO PARSE
use Whostmgr::Accounts::Create::Components::HomeDir         ();    # PPI NO PARSE
use Whostmgr::Accounts::Create::Components::Mail            ();    # PPI NO PARSE
use Whostmgr::Accounts::Create::Components::SystemUser      ();    # PPI NO PARSE
use Whostmgr::Accounts::Create::Components::Userdata        ();    # PPI NO PARSE

# Order here *is* important!
my @module_list = qw{
  SystemUser
  Userdata
  HomeDir
  Mail
  CalendarContact
};
my $ns = 'Whostmgr::Accounts::Create::Components';

=head1 SUBROUTINES

=head2 get

returns LIST of OBJECTS of type Whostmgr::Accounts::Create::Components::*

=cut

sub get {
    return map { "${ns}::$_"->new() } @module_list;
}

1;
