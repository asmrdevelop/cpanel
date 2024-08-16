package Whostmgr::Accounts::Suspend;

# cpanel - Whostmgr/Accounts/Suspend.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A modular system for account suspension.
#
# See POD below.
#----------------------------------------------------------------------

use strict;

use base qw(
  Whostmgr::Accounts::Suspension::Base
);

sub new {
    my ( $class, $username ) = @_;

    return $class->_init_and_do_action(
        username    => $username,
        action      => 'suspend',
        undo_action => 'unsuspend',
    );
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Suspend

=head1 DESCRIPTION

cPanel account suspension

=head1 SYNOPSIS

    my $suspension = Whostmgr::Accounts::Suspend->new($username);

    $suspension->get('username');
    $suspension->get('action');     #"suspend"

=head1 DISCUSSION

This module should eventually replace C</scripts/suspendacct>
as the logic for coordinating account suspensions.

It calls into the different “helper” modules and executes the C<suspend()> action in each.

Should that “action” function throw an exception, C<Whostmgr::Accounts::Suspend>
will attempt to roll back the changes that have thus far been made using C<Cpanel::Rollback>,
then rethrow the original exception. Any rollback failures are attached to the original exception.
(This is a best-attempt at avoiding “partially suspended” accounts.)

=head1 UNSUSPENSION

Unsuspension is handled via the C<Whostmgr::Accounts::Unsuspend> module, which has exactly
the same interface as this one and whose functionality is retrograde to this one.

=head1 HELPER MODULE INTERFACE

The private method C<_helper_modules_to_use()> (currently in a base class) gives the names of
modules to include. It is implied that these modules will live under the namespace given by the
C<_helper_module_namespace_root()> private method.

Each helper module should define a C<suspend()> function. This function will receive the username
as an argument. The function’s return value is currently ignored. The same module should also
define an C<unsuspend()> function that undoes C<suspend()>’s action.

=cut
