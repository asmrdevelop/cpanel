package Cpanel::Debug;

# cpanel - Cpanel/Debug.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Debug - Log messages

=head1 DESCRIPTION

This module provides logging logic that automatically handles an internal
L<Cpanel::Logger> singleton.

NB: This function’s interface is not fully documented yet.

=cut

#----------------------------------------------------------------------

our $HOOKS_DEBUG_FILE = '/var/cpanel/debughooks';

our $level = ( exists $ENV{'CPANEL_DEBUG_LEVEL'} && $ENV{'CPANEL_DEBUG_LEVEL'} ? int $ENV{'CPANEL_DEBUG_LEVEL'} : 0 );

#----------------------------------------------------------------------

=head1 FUNCTIONS

=cut

my $debug_hooks_value;
my $logger;

=head2 debug_level

Returns $Cpanel::Debug::level (or sets it). Useful for those times you don't
wanna disable warnings just to get updatenow to not whine about using it 'once'.
Pass in a defined value to set it manually as well.

=cut

sub debug_level {
    my ($level) = @_;
    $Cpanel::Debug::level = $level if defined $level;
    return $Cpanel::Debug::level;
}

sub logger {
    $logger = shift if (@_);    # Set method for $logger if something is passed in.

    return $logger ||= do {
        local ( $@, $! );
        require Cpanel::Logger;

        Cpanel::Logger->new();
    };
}

sub log_error {
    local $!;                   #prevent logger from overwriting $!
    return logger()->error( $_[0] );
}

=head2 log_warn( $MESSAGE )

A passthrough to L<Cpanel::Logger>’s C<warn()> method.

B<IMPORTANT:> This function “tightly couples” to cPanel & WHM’s main log
file. If you’re writing code that may be called in multiple contexts, it’s
probably better to use plain warn() than this function. Then, in the
context-aware calling code,
create a L<Cpanel::WarnToLog> instance that will send all warn()ings to the
log. That way code that I<shouldn’t> send warnings to the log can handle
them however is appropriate as per context.

=cut

sub log_warn {
    local $!;    #prevent logger from overwriting $!
    return logger()->warn( $_[0] );
}

sub log_warn_no_backtrace {
    local $!;    #prevent logger from overwriting $!

    my $logger = logger();

    local $Cpanel::Logger::ENABLE_BACKTRACE = 0;

    return $logger->warn( $_[0] );
}

sub log_invalid {
    local $!;    #prevent logger from overwriting $!
    return logger()->invalid( $_[0] );
}

sub log_deprecated {
    local $!;    #prevent logger from overwriting $!
    return logger()->deprecated( $_[0] );
}

sub log_panic {
    local $!;    #prevent logger from overwriting $!
    return logger()->panic( $_[0] );
}

sub log_die {
    local $!;    #prevent logger from overwriting $!
    return logger()->die( $_[0] );
}

sub log_info {
    local $!;    #prevent logger from overwriting $!
    return logger()->info( $_[0] );
}

sub log_debug {
    local $!;    #prevent logger from overwriting $!
    return logger()->debug( $_[0] );
}

sub debug_hooks_value {
    return $debug_hooks_value if defined $debug_hooks_value;
    return ( $debug_hooks_value = ( stat($HOOKS_DEBUG_FILE) )[7] || 0 );
}

1;
