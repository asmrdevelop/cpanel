package Whostmgr::Update::BlockerFile;

# cpanel - Whostmgr/Update/BlockerFile.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 Whostmgr::Update::BlockerFile

Utility function for reading /var/cpanel/update_blocks.config in such a way
that multi-line update blockers are displayed correctly by WHM.

The messages returned will be HTML.

=cut

use strict;
use warnings;

use Cpanel::Debug ();

#Allow configuration by testers
our $UPDATE_BLOCKS_CACHE;
our $UPDATE_BLOCKS_FNAME = '/var/cpanel/update_blocks.config';

=head1 FUNCTIONS

=head2 parse

Return an ARRAYREF of HASHREFs containing a severity and message attribute.

Each entry in the arrayref corresponds to a line starting with a valid severity followed by a comma.
Any amount of data can proceed past said comma until a new line starting with a valid severity and a comma is encountered.

Valid severities are 'quiet', 'quiet_error', 'info' and 'fatal'.

Messages are output with HTML line breaks.

=cut

sub parse {
    my $logger = shift;
    return $UPDATE_BLOCKS_CACHE if defined $UPDATE_BLOCKS_CACHE;

    my @messages;
    if ( -e $UPDATE_BLOCKS_FNAME ) {
        if ( my $fh = _get() ) {
            while ( my $line = scalar <$fh> ) {
                chomp($line);
                my ( $severity, $message ) = split( ',', $line, 2 );

                # Sanitize, we could have a lot of slop here
                $severity = _trim($severity);
                $message  = _trim($message);

                if ( $severity && grep { $_ eq $severity } qw{info quiet quiet_error fatal} ) {
                    push @messages, { severity => $severity, message => $message };
                }
                else {
                    # Looks like we have a piece of a message instead.
                    $messages[-1]->{'message'} .= "<br />$line" if @messages;
                }
            }

            close($fh);

            # Cache
            $UPDATE_BLOCKS_CACHE = \@messages;
            return $UPDATE_BLOCKS_CACHE;
        }
        else {
            if ($logger) {
                $logger->warn("Unable to read $UPDATE_BLOCKS_FNAME: $!");
            }
            else {
                Cpanel::Debug::log_warn("Unable to read $UPDATE_BLOCKS_FNAME: $!");
            }
        }
    }
    return;
}

sub _get {
    my $rc = open( my $fh, '<', $UPDATE_BLOCKS_FNAME );
    return $rc ? $fh : undef;
}

sub _trim {
    my $string = shift;

    return unless defined $string;

    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

1;
