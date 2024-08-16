package Whostmgr::Transfers::Session::Constants;

# cpanel - Whostmgr/Transfers/Session/Constants.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Transfer::Session::Constants - Constants needed for Whostmgr::Transfers::Session

=head1 SYNOPSIS

    use Whostmgr::Transfer::Session::Constants;

=head1 DESCRIPTION

This module provides the constants needed to setup a transfer session
without the need to load the entire Whostmgr::Transfer::Session module.

=cut

our @QUEUES = (
    'TRANSFER',
    'RESTORE',
);

our %QUEUE_COMPLETED_STATES = (
    'TRANSFER' => 'RESTORE_PENDING',
    'RESTORE'  => 'COMPLETED'
);

# If additional STATES are added, transfer_sessions_review.tmpl will need
# to be updated if new STATE is required to be displayed in logs
our %QUEUE_STATES = (
    'TRANSFER_PENDING'    => 0,
    'TRANSFER_INPROGRESS' => 10,

    'RESTORE_PENDING'    => 30,
    'RESTORE_INPROGRESS' => 40,

    'COMPLETED' => 100,
    'FAILED'    => 200,

);

our %SESSION_TYPES = (
    'RemoteRoot' => 1,
    'RemoteUser' => 2,
    'Local'      => 4,
    'Upload'     => 8,
    'Legacy'     => 16,
);

our $QUEUE_BLOCKED = -1;
our $QUEUE_EMPTY   = 0;
our $QUEUE_FETCHED = 1;

our %SESSION_TYPE_NAMES = reverse %SESSION_TYPES;

# Items are processed in ASC order
our $HIGHEST_PRIORITY = 1;     # we want one that will work with ||=
our $LOWEST_PRIORITY  = 255;

our $MIN_VALID_RETURN_CODE = $Whostmgr::Transfers::Session::Constants::QUEUE_STATES{'TRANSFER_INPROGRESS'};

our $USER_TRANSFERRED_MESSAGE = 'User transferred to another server';

use constant {
    ROOT_API_SESSION_INITIATOR => 'copyacct',
    USER_API_SESSION_INITIATOR => 'norootcopy',
};

1;
