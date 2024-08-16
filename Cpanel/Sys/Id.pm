package Cpanel::Sys::Id;

# cpanel - Cpanel/Sys/Id.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf8

=head1 NAME

Cpanel::Sys::Id - Pure perl implementation of setresgid,setresuid,setgroups

=head1 SYNOPSIS

=cut

use strict;
use warnings;
use Cpanel::Pack::Template ();    # PPI USE OK - in use constant
use Cpanel::Syscall        ();

use constant PACK_TEMPLATE_UNSIGNED_INT => Cpanel::Pack::Template::PACK_TEMPLATE_UNSIGNED_INT();

=head2 setresgid

See system setresgid. This is just a thin wrapper.

=cut

sub setresgid {
    return Cpanel::Syscall::syscall( 'setresgid', int $_[0], int $_[1], int $_[2] );
}

=head2 setresuid

See system setresuid. This is just a thin wrapper.

=cut

sub setresuid {
    return Cpanel::Syscall::syscall( 'setresuid', int $_[0], int $_[1], int $_[2] );
}

=head2 setgroups

See system setgroups. This is just a thin wrapper.

=cut

sub setgroups {
    return Cpanel::Syscall::syscall( 'setgroups', scalar @_, pack( PACK_TEMPLATE_UNSIGNED_INT x scalar @_, @_ ) );
}

1;
