package Cpanel::PHPFPM::RebuildQueue;

# cpanel - Cpanel/PHPFPM/RebuildQueue.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::PHPFPM::RebuildQueue

=head1 SYNOPSIS

(See subclasses.)

=head1 DESCRIPTION

The Enable Sub Queue is designed to queue all the domains that we
want to rebuild the PHP-FPM configs on.

=cut

use parent qw( Cpanel::TaskQueue::SubQueue );

our $_DIR = '/var/cpanel/taskqueue/groups/rebuild_fpm_subqueue';

sub _DIR { return $_DIR; }

1;
