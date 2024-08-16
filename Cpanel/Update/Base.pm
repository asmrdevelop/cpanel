package Cpanel::Update::Base;

# cpanel - Cpanel/Update/Base.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Update::Base - A base call for cPanel updates.

=head1 DESCRIPTION

This class is used by the update sync and rpm management systems.

=cut

our $VERSION = '1.00';
our $MAX_NUM_SYNC_CHILDREN;                                                                                   # will be calculated below
our $MAX_NUM_SYNC_CHILDREN_WITHOUT_FAST_UPDATE = 1;
our $MAX_NUM_SYNC_CHILDREN_WITH_FAST_UPDATE    = 16;
our $SYNC_CHILD_MAX_MEMORY_NEEDED              = 80;                                                          # In MegaBytes (this has a lot of buffer built in)
our $FAST_UPDATE_NEVER_EVER_FLAG_FILE          = '/var/cpanel/never_ever_use_fast_update_not_even_a_check';

=head2 calculate_max_sync_children()

Returns the number of sync children this sytem can safely handle without OOM

=cut

sub calculate_max_sync_children {
    my ($self) = @_;
    require Cpanel::Sys::Hardware::Memory;
    my $available_memory_in_megabytes                   = Cpanel::Sys::Hardware::Memory::get_available();
    my $max_num_of_sync_children_this_system_can_handle = int( ( $available_memory_in_megabytes - $SYNC_CHILD_MAX_MEMORY_NEEDED ) / $SYNC_CHILD_MAX_MEMORY_NEEDED );
    $max_num_of_sync_children_this_system_can_handle = 1 unless $max_num_of_sync_children_this_system_can_handle >= 1;

    my $max_num_client = $self->_get_max_num_client();
    if ( $max_num_of_sync_children_this_system_can_handle > $max_num_client ) {
        $max_num_of_sync_children_this_system_can_handle = $max_num_client;
    }
    $self->logger()->info("Maximum sync children set to $max_num_of_sync_children_this_system_can_handle based on ${available_memory_in_megabytes}M available memory.");
    return $max_num_of_sync_children_this_system_can_handle;
}

sub logger {
    my $self = shift or die;
    return $self->{'logger'};
}

# Tested directly
sub _get_max_num_client {
    my ($self) = @_;

    return $MAX_NUM_SYNC_CHILDREN_WITHOUT_FAST_UPDATE unless $self->_can_use_fastupdate();
    return $MAX_NUM_SYNC_CHILDREN if $MAX_NUM_SYNC_CHILDREN;

    require Cpanel::Cpu;
    my $cpu = Cpanel::Cpu::getcpucount();

    # For systems with higher latency on the other size of the world
    # from the update system, the number of children makes a difference
    # in performance even though it cannot decompress any faster since
    # there will be more wait time between send and recieve
    $MAX_NUM_SYNC_CHILDREN = 8 * int($cpu);

    # hard limit to 16
    $MAX_NUM_SYNC_CHILDREN = 16 if $MAX_NUM_SYNC_CHILDREN > 16;
    return $MAX_NUM_SYNC_CHILDREN;
}

sub _can_use_fastupdate {
    return 1 if ( !-e $FAST_UPDATE_NEVER_EVER_FLAG_FILE );
    return 0;
}

1;
