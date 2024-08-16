package Cpanel::ProcessLog::WithChildError;

# cpanel - Cpanel/ProcessLog/WithChildError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::ProcessLog';

use Cpanel::Time::ISO ();

our $DIR = '/var/cpanel/logs';

sub _DIR { return $DIR }

use constant _METADATA_SCHEMA => (
    'CHILD_ERROR',    #string/number
);

*_get_isotime = \*Cpanel::Time::ISO::unix2iso;

# Prefix can be a suffix, whatever you wanna do with it really.
# Just subclass to override.
sub _new_log_id_and_metadata {
    my ( $class, $prefix, @args_kv ) = @_;

    #diverges from SSL::Auto
    return (
        join( '_', $prefix, _get_isotime() ),
        @args_kv,
    );
}

=encoding utf-8

=head1 NAME

Cpanel::ProcessLog::WithChildError - Subclass of Cpanel::ProcessLog meant
to help you keep track of metadata indicating some kind of exit code from
the process which is writing to a given log.

=head1 SYNOPSIS

    # Will look like 'My_Super_Cool_Log_category_$SOME_ZULU_TIME_STRING'
    my $log_entry = Cpanel::ProcessLog::WithChildError->create_new(
        'My_Super_Cool_Log_category',
        'CHILD_ERROR' => '?',
    );

    my $metadata_hr = Cpanel::ProcessLog::WithChildError->get_metadata('some-description');

    Cpanel::ProcessLog::WithChildError->set_metadata( 'some-description', CHILD_ERROR => 0 );

    Cpanel::ProcessLog::WithChildError->redirect_stdout_and_stderr('some-description');

    my $read_fh = Cpanel::ProcessLog::WithChildError->open('some-description');

=head1 DESCRIPTION

This module is a generalization of the logging logic originally implemented
in the L<Cpanel::Plugins::Log>'s _CLASS subpackage. It’s useful in contexts where
we want to report a process’s output as well as its exit state in more than
just Cpanel::Plugins::Log's context.

Just as with Cpanel::Plugins::Log, there was an attempt to abstract away the
storage details, though it’s a fairly weak abstraction.

An individual log instance is still referred to as a log “instance”.

=head1 SEE ALSO

Cpanel::Server::WebSocket::whostmgr::LogStreamer
Cpanel::Plugins::Log

=cut

1;
