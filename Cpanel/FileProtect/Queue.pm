package Cpanel::FileProtect::Queue;

# cpanel - Cpanel/FileProtect/Queue.pm          Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::FileProtect::Queue;

=head1 SYNOPSIS

(See subclasses.)

=head1 DESCRIPTION

We want to be able to do all the fileprotect
operations in a single subprocess to reduce
the perl load overhead.

=cut

use parent qw( Cpanel::TaskQueue::SubQueue );

our $_DIR = '/var/cpanel/taskqueue/groups/fileprotect';

sub _DIR { return $_DIR; }

1;
