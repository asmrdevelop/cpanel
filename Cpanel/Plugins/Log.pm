package Cpanel::Plugins::Log;

# cpanel - Cpanel/Plugins/Log.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Plugins::Log

=head1 SYNOPSIS

    my $log_entry = Cpanel::Plugins::Log::create_new(
        'some-description',
        CHILD_ERROR => '?',
    );

    my $metadata_hr = Cpanel::Plugins::Log::get_metadata('some-description');

    Cpanel::Plugins::Log::set_metadata( 'some-description', CHILD_ERROR => 0 );

    Cpanel::Plugins::Log::redirect_stdout_and_stderr('some-description');

=head1 DESCRIPTION

This module governs access to the log entries for WHM plugins. It uses the
backend logic from L<Cpanel::ProcessLog::WithChildError>.

=cut

#overridden in tests
our $_DIR = '/var/cpanel/logs/plugin';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $entry_name = create_new( DESCRIPTOR, METADATA_KEY1 => VALUE1, … )

Creates a new log entry. DESCRIPTOR is a short “key” to describe this
value. A timestamp will be added.

The return is a string to use as LOG_ENTRY in other calls.

=cut

sub create_new {
    my ( $suffix, @kv ) = @_;

    return Cpanel::Plugins::Log::_CLASS->create_new( $suffix, @kv );
}

#----------------------------------------------------------------------

=head2 $metadata_hr = set_metadata( LOG_ENTRY, CHILD_ERROR => VAL )

Sets the log entry’s metadata. Currently the only metadata parameter is
C<CHILD_ERROR>; if this module is refactored to suit other applications,
there could be other entries.

=cut

sub set_metadata {
    return Cpanel::Plugins::Log::_CLASS->set_metadata(@_);
}

#----------------------------------------------------------------------

=head2 redirect_stdout_and_stderr( LOG_ENTRY )

Sets the global STDOUT and STDERR filehandles to append to the log
indicated by LOG_ENTRY, and sets those filehandles to autoflush mode.

Call this at the beginning of a log process.

=cut

sub redirect_stdout_and_stderr {
    return Cpanel::Plugins::Log::_CLASS->redirect_stdout_and_stderr(@_);
}

#----------------------------------------------------------------------

package Cpanel::Plugins::Log::_CLASS;

use parent 'Cpanel::ProcessLog::WithChildError';

use Cpanel::Time::ISO;

sub _DIR { return $Cpanel::Plugins::Log::_DIR }

*_get_isotime = \*Cpanel::Time::ISO::unix2iso;

sub _new_log_id_and_metadata {
    my ( $class, $suffix, @args_kv ) = @_;

    #diverges from SSL::Auto
    return (
        join( '_', _get_isotime(), $suffix ),
        @args_kv,
    );
}

1;
