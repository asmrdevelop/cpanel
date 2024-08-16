package Cpanel::Logs::ErrorEvents;

# cpanel - Cpanel/Logs/ErrorEvents.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Logs::ErrorEvents

=head1 DESCRIPTION

Analyze one error log and look for error line like

   [2017-12-20 14:34:27 +0000] E    [/a/script] some text

then report the list of failed events with some extra informations
( line matching and last error line)

=head1 SUBROUTINES

=head2 Cpanel::Logs::ErrorEvents::extract_events_from_log

Input: the input is passed as a hash

=over 4

=item log: log content (scalar or reference to a scalar) - mandatory

=item after_line: where to start looking for errors - optional, default value 0

=item max_lines: number of error lines to return - optional, default value 0

=back

Output: the return value is a list containing three arguments

=over 4

=item events: array ref (or undef) - list of error events

=item error_lines: array ref - list of error lines matching the (E) regexp (default value is [])

=item last_line_number_used - last line from the error lines extract (default value is 1)

=back

=head3 Sample usage:

    my ( $events, $error_lines, $last_line_number_used )
        = extract_events_from_log( log => "My Log\nLine 2\n" );

    ( $events, $error_lines, $last_line_number_used )
        = extract_events_from_log( log => "My Log\nLine 2\n", after_line => 2, max_lines => 1 );

=cut

sub extract_events_from_log {
    my (%opts) = @_;

    my $log        = $opts{log};
    my $after_line = $opts{after_line} || 0;
    my $max_lines  = $opts{max_lines}  || 0;

    return unless defined $log;

    $log = $$log if ref $log eq 'SCALAR';
    my @lines = split( m{\n}, $log );

    my $line_number = 1;
    my %events;
    my $last_line_number_used = $line_number;

    my @error_lines;

    foreach my $line (@lines) {
        next if $line_number <= $after_line;    # discard the beginning of the log (could use split)

        # does the line looks like an error -- looks for line like '[2017-12-20 04:48:31 +1100] E    [''
        next unless $line =~ qr{^\s*\[[^\]]+\]\s+E\s+\[([^\]]+)};

        # add all the events after the $after_line to the hash
        my $script = $1;
        $script =~ s{^/usr/local/cpanel/}{};    # make the name shorter by removing cpanel path
        $events{$script} = 1;

        # only get the first x line
        if ( !$max_lines || scalar @error_lines < $max_lines ) {
            push @error_lines, qq{...} if $last_line_number_used != $line_number;
            push @error_lines, $line;
            $last_line_number_used = $line_number + 1;
        }

    }
    continue {
        ++$line_number;
    }

    my $events_as_array = keys %events ? [ sort keys %events ] : undef;

    return ( $events_as_array, \@error_lines, $last_line_number_used );
}

1;
