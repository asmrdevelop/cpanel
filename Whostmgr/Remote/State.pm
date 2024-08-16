package Whostmgr::Remote::State;

# cpanel - Whostmgr/Remote/State.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Remote::State - Global state for the Whostmgr::Remote module.

=head1 SYNOPSIS

    use Whostmgr::Remote::State;

    local $Whostmgr::Remote::State::HTML = 0;

    $Whostmgr::Remote::State::last_active_host = 'host';

=head1 DESCRIPTION

This module provides legacy compatibilty for code that is unaware
of Whostmgr::Remote objects.  This is a intermediary point that
will allow us easily identify and get rid of module that are using
the old methods.

=cut

our $HTML = 1;
our $last_active_host;

# Constants
# The UI always displays lines that start with ^ERROR: in red.
our $ERROR_PREFIX = "ERROR: ";
our $UTF8_LOCALE  = 'en_US.UTF-8';

1;
