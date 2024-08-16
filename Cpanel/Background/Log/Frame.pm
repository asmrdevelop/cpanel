
# cpanel - Cpanel/Background/Log/Frame.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Background::Log::Frame;

use strict;
use warnings;

use Cpanel::JSON ();

=head1 MODULE

C<Cpanel::Background::Log::Frame>

=head1 DESCRIPTION

C<Cpanel::Background::Log::Frame> provides a class to build a single log message frame.

=head1 SYNOPSIS

  use Cpanel::Background::Log::Frame;
  my $frame = Cpanel::Background::Log::Frame->new();
  print $frame->serialize();

=head1 CONSTRUTOR

=head2 new(type => ..., name => ..., data => ...)

Construct a new frame.

=cut

sub new {
    my ( $class, %args ) = @_;
    my $self = {%args};
    bless $self, $class;
    return $self;
}

=head1 PROPERTIES

=head2 type - string

Getter. Type of message in the frame.

=cut

sub type {
    my $self = shift;
    return $self->{type};
}

=head2 name - string

Getter. Name of message in the frame.

=cut

sub name {
    my $self = shift;
    return $self->{name};
}

=head2 data - string

Getter. Data associated with the message in the frame.

=cut

sub data {
    my $self = shift;
    return $self->{data};
}

=head1 METHODS

=head2 merge_data(DATA)

Merge the data passed in, with the data current stored in the frame.

=head3 ARGUMENTS

=over

=item DATA - hashref

Collection of properties to merge into the data set. These properties will override
any existing properties passed to data in the constructor.

=back

=cut

sub merge_data {
    my ( $self, $data ) = @_;

    my %data = (
        ( defined $self->data && ref $self->data eq 'HASH' ? %{ $self->data } : () ),
        ( defined $data       && ref $data eq 'HASH'       ? %{$data}         : () ),
    );
    $self->{data} = \%data;

    return 1;
}

=head2 serialize()

Generate a complete frame in wire format which is a JSON object followed by a linefeed.

 { type => ..., [name => ...], [data => { ... }]}\n

were name and data are optional depending on how the frame is initialized.

=head3 RETURNS

string

=cut

sub serialize {
    my $self = shift;

    my $frame = {
        type => $self->type,
        ( $self->name                                                       ? ( name => $self->name ) : () ),
        ( $self->data && ref $self->data eq 'HASH' && keys %{ $self->data } ? ( data => $self->data ) : () ),
    };

    return Cpanel::JSON::Dump($frame) . "\n";
}

1;
