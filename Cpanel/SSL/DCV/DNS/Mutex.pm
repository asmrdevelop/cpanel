package Cpanel::SSL::DCV::DNS::Mutex;

# cpanel - Cpanel/SSL/DCV/DNS/Mutex.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DCV::DNS::Mutex

=head1 SYNOPSIS

    my $mutex = Cpanel::SSL::DCV::DNS::Mutex->new('bob');

=head1 DESCRIPTION

This class defines an advisory mutex for DNS DCV on a given user’s domains.

It subclasses L<Cpanel::UserMutex>.

=head1 SUBCLASS INTERFACE

Currently all that’s required is to subclass this module.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::UserMutex );

1;
