package Cpanel::LinkedNode::Convert::Mutex;

# cpanel - Cpanel/LinkedNode/Convert/Mutex.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::Mutex

=head1 SYNOPSIS

    my $mutex = Cpanel::LinkedNode::Convert::Mutex->new('bob');

=head1 DESCRIPTION

A mutex that ensures that a given user is only converted to/from linked-node
configuration by one process at a time.

It subclasses L<Cpanel::UserMutex>.

=head1 SUBCLASS INTERFACE

Currently all that’s required is to subclass this module.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::UserMutex::Privileged );

#----------------------------------------------------------------------

1;
