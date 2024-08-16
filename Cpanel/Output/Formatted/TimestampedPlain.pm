package Cpanel::Output::Formatted::TimestampedPlain;

# cpanel - Cpanel/Output/Formatted/TimestampedPlain.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::Output::Formatted::TimeStamp
  Cpanel::Output::Formatted::Plain
);

=encoding utf-8

=head1 NAME

Cpanel::Output::Formatted::TimestampedPlain

=head1 DESCRIPTION

This module is meant to be used with the Cpanel::Output system to create a timestamped log file.

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
