package Whostmgr::Accounts::Unsuspend;

# cpanel - Whostmgr/Accounts/Unsuspend.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A modular system for account unsuspension.
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
        action      => 'unsuspend',
        undo_action => 'suspend',
    );
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Unsuspend

=head1 DESCRIPTION

cPanel account unsuspension

=head1 SYNOPSIS

    #Same interface as Whostmgr::Accounts::Suspend

=head1 DISCUSSION

This module should eventually replace C</scripts/unsuspendacct>
as the logic for coordinating account unsuspensions.

See documentation for C<Whostmgr::Accounts::Suspend> for more details and examples;
wherever that documentation says something about “suspend”, just interpret it as
“unsuspend”, and that will describe this module.

=cut
