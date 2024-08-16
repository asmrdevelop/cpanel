package Cpanel::QueueProcd::Global;

# cpanel - Cpanel/QueueProcd/Global.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::QueueProcd::Global - manage queueprocd’s global state

=head1 SYNOPSIS

    use Cpanel::QueueProcd::Global ();

    Cpanel::QueueProcd::Global::reload_plugins();

    Cpanel::QueueProcd::Global::set_status_msg('doing something');

=cut

my @plugindirs = ( '/var/cpanel/perl', '/usr/local/cpanel' );
my @namespaces = ('Cpanel::TaskProcessors');

=head2 reload_plugins()

Load the TaskProcessor plugins again, in case there are new processors.

=cut

sub reload_plugins {
    return Cpanel::TaskQueue::PluginManager::load_all_plugins(    # PPI USE OK -- Cpanel::TaskQueue::PluginManager should already be loaded by the time this module is
        directories => \@plugindirs,
        namespaces  => \@namespaces,
    );
}

=head2 set_status_msg()

Make setting of program name as status message more consistent.

=cut

sub set_status_msg {
    my ($msg) = @_;
    $0 = "queueprocd - $msg";    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
    return;
}

1;
