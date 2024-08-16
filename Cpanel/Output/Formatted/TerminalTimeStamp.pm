package Cpanel::Output::Formatted::TerminalTimeStamp;

# cpanel - Cpanel/Output/Formatted/TerminalTimeStamp.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Output::Formatted::TerminalTimeStamp - Output to a terminal with timestamps

=head1 SYNOPSIS

    use Cpanel::Output::Formatted::TerminalTimeStamp;

    my $obj = Cpanel::Output::Formatted::TerminalTimeStamp->new( 'timestamp_method' => sub { return time() } )

=cut

use parent qw( Cpanel::Output::Formatted::TimeStamp Cpanel::Output::Formatted::Terminal );

=head2 message(...)

An internal function that provides the underlying Cpanel::Output functionality
to prepend the timestamp.  This method should not be called directly, instead use
info, warn, output, or error.

=cut

sub message {
    my ( $self, $message_type, $msg_contents, $source, $partial_message ) = @_;

    return $self->SUPER::message(
        $message_type,
        $msg_contents,
        $source,
        $partial_message,
        $Cpanel::Output::PREPENDED_MESSAGE,
    );
}

1;

__END__
