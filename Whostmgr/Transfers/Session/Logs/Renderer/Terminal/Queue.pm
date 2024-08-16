package Whostmgr::Transfers::Session::Logs::Renderer::Terminal::Queue;

# cpanel - Whostmgr/Transfers/Session/Logs/Renderer/Terminal/Queue.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module prints log data from a tranfer or restore operation to the
# console. This is not for the "master" log file but for the individual
# TRANSFER or RESTORE log files.
#----------------------------------------------------------------------

use strict;

use base 'Whostmgr::Transfers::Session::Logs::Renderer::Terminal::Master';

use Cpanel::JSON                      ();
use Cpanel::Locale                    ();
use Cpanel::Output::Restore::Terminal ();

my $locale;

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = {
        _renderer => Cpanel::Output::Restore::Terminal->new( 'parent' => $OPTS{'parent'} ),
    };

    return bless $self, $class;
}

#
#
#NOTE: If the passed-in message is a "summary", then this object collects that
#summary data rather than printing anything. You can then print the summary
#data by calling render_summary().
sub render_message {
    my ( $self, $message ) = @_;

    my $renderer = $self->{'_renderer'};

    my $entry;
    local $@;

    # This renders every line in a transfer so try {} can take
    # too long
    eval {
        $entry = Cpanel::JSON::Load($message);
        die if !ref $entry || ref $entry ne 'HASH';
    };
    if ($@) {
        $renderer->message( 'error', { msg => "Invalid log entry: [$message]" } );
    }

    return if !$entry || !ref $entry || ref $entry ne 'HASH';

    if ( $entry->{'contents'}{'action'} ) {
        if ( $entry->{'contents'}{'action'} eq 'summary' ) {
            $self->{'_summary'} = $entry->{'contents'};
            return;
        }
    }

    $renderer->message( @{$entry}{qw( type contents source )} );

    return;
}

#A no-op unless render_message() has found summary data in one of the messages
#that it has received.
sub render_summary {
    my ($self) = @_;

    my $summary = $self->{'_summary'};

    return if !$summary;

    my $renderer = $self->{'_renderer'};

    $renderer->reset();

    #NOTE: These data structures are *almost* complex enough that it would seem
    #prudent to create classes that abstract the structure away.

    for my $record ( @{ $summary->{'warnings'} } ) {
        $renderer->message(
            'warn',
            {
                'msg' => [
                    _locale()->maketext( "Warning (“[_1]”, line [numf,_2]): [_3]", join( '::', @{ $record->[0] }[ 0, 1 ] ), $record->[0][2], $record->[1] ) . "\n",
                ]
            }
        );
    }

    for my $record ( @{ $summary->{'skipped_items'} } ) {
        $renderer->message(
            'warn',
            {
                'msg' => [
                    _locale()->maketext( "Skipped item (“[_1]”, line [numf,_2]): [_3]", join( '::', @{ $record->[0] }[ 0, 1 ] ), $record->[0][2], $record->[1] ) . "\n",
                ]
            }
        );
    }

    for my $record ( @{ $summary->{'altered_items'} } ) {
        $renderer->message(
            'warn',
            {
                'msg' => [
                    _locale()->maketext( "Altered item (“[_1]”, line [numf,_2]): [_3]", join( '::', @{ $record->[0] }[ 0, 1 ] ), $record->[0][2], $record->[1] ) . "\n",
                ]
            }
        );
    }

    for my $record ( @{ $summary->{'dangerous_items'} } ) {
        $renderer->message(
            'error',
            {
                'msg' => [
                    _locale()->maketext( "[output,strong,Dangerous] item (“[_1]”, line [numf,_2]): [_3]", join( '::', @{ $record->[0] }[ 0, 1 ] ), $record->[0][2], $record->[1] ) . "\n",
                ]
            }
        );
    }

    return;
}

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

1;
