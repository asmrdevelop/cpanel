package Cpanel::LogTailer::Client;

# cpanel - Cpanel/LogTailer/Client.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Locale ();

##########################################################################################
# This class is intended to be a base class for consuming a log tailer implementation.
##########################################################################################

=head1 NAME

Cpanel::LogTailer::Client

=head1 DESCRIPTION

A base class for consuming streaming tailed logs.

=head1 METHODS

=head2 get_buffer

=head3 Purpose

    Gets the current buffer state of the object.

=head3 Arguments

    None

=head3 Exceptions

    None

=head3 Returns

    A scalar ref of the current buffer. If no buffer is set, then it returns a scalar ref to an empty string.

=cut

sub get_buffer {
    my ($self) = @_;

    return $self->{_buffer} if $self->{_buffer};

    my $buffer = q{};

    return $self->{_buffer} = \$buffer;
}

=head2 get_log_file_data

=head3 Purpose

    Gets the log file data set in the object.

=head3 Arguments

    None

=head3 Exceptions

    None

=head3 Returns

    The log data of the current object. This is usually a hashref describing the log files and the client's current position in streaming them.
    Please see implementations of this base class for more details of what the log data should look like.

=cut

sub get_log_file_data {
    my ($self) = @_;

    return $self->{log_file_data};
}

=head2 get_sentinel_data

=head3 Purpose

    Gets the set sentinel data of the object. Sentinel data is used to terminate the processing loop.

=head3 Arguments

    None

=head3 Exceptions

    None

=head3 Returns

    The sentinel data of the object. This is usually a hashref containing data used to track the conditions to end the processing loop.
    Please see implementations of this base class for more details of what the sentinel data should look like.

=cut

sub get_sentinel_data {
    my ($self) = @_;

    return $self->{_sentinel_data};
}

=head2 set_sentinel_data

=head3 Purpose

    Sets the set sentinel data for the object. Sentinel data is used to terminate the processing loop.

=head3 Arguments

    A hashref (usually) of sentinel data used to track the conditions to end the processing loop.
    Please see implementations of this base class for more details of what the sentinel data should look like.

=head3 Exceptions

    None

=head3 Returns

    Nothing.

=cut

sub set_sentinel_data {
    my ( $self, $data ) = @_;

    $self->{_sentinel_data} = $data;

    return 1;
}

=head2 read_log_stream

=head3 Purpose

    The main processing loop of the streaming log data to be overridden in child classes. Please see implementations for more details.

=head3 Arguments

    Varies by implementation.

=cut

sub read_log_stream {
    ...;
}

sub _locale {
    my ($self) = @_;

    return ( $self->{_locale} ||= Cpanel::Locale->get_handle() );
}

sub _get_termination_integer {
    ...;
}

sub _get_termination_sequence {
    ...;
}

1;
