package Cpanel::Dovecot::FlushcPanelAccountAuthQueue;

# cpanel - Cpanel/Dovecot/FlushcPanelAccountAuthQueue.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::FlushcPanelAccountAuthQueue;

=head1 SYNOPSIS

(See subclasses.)

=head1 DESCRIPTION

This module provides a subqueue for clearing the auth cache for all the accounts
that a cPanel user owns.  If you need to clear the auth for a specific user without
all the accounts the cPanel user owns, FlushAuthQueue should be used

=cut

use parent qw( Cpanel::TaskQueue::SubQueue );

our $_DIR = '/var/cpanel/taskqueue/groups/flush_cpanel_account_dovecot_auth_cache';

sub _DIR { return $_DIR; }

1;
