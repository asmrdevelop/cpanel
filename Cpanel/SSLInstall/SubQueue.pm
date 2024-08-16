package Cpanel::SSLInstall::SubQueue;

# cpanel - Cpanel/SSLInstall/SubQueue.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSLInstall::SubQueue

=head1 DESCRIPTION

This namespace’s L<Cpanel::SSLInstall::SubQueue::Adder> and
L<Cpanel::SSLInstall::SubQueue::Harvester> modules implement a subqueue
for SSL installations.

The subqueue’s keys are vhost names. Each value is an arrayref of:

=over

=item * username

=item * key, in PEM format

=item * certificate, in PEM format

=item * CA bundle, in newline-joined PEM format. May also be undef.

=back

=cut

our $_DIR = '/var/cpanel/taskqueue/groups/sslinstall';

sub _DIR { return $_DIR; }

1;
