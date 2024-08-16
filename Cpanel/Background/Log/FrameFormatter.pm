
# cpanel - Cpanel/Background/Log/FrameFormatter.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Background::Log::FrameFormatter;

use strict;
use warnings;

use Cpanel::Background::Log::Frame ();

=head1 MODULE

C<Cpanel::Background::Log::FrameFormatter>

=head1 DESCRIPTION

C<Cpanel::Background::Log::FrameFormatter> provides a formatter interface that serializes
data from the internal format to the Frame format.

=head1 SYNOPSIS

  use Cpanel::Background::Log::FrameFormatter;
  my msg = Cpanel::Background::Log::FrameFormatter::format(type, name, data);

=head1 FUNCTIONS

=head2 format

=head3 ARGUMENTS

=over

=item type - string

=item name - string

=item data - hashref

=back

=head3 RETURNS

String - serialized frame.

=cut

sub format {
    my ( $type, $name, $data ) = @_;
    return Cpanel::Background::Log::Frame->new(
        type => $type,
        name => $name,
        data => $data,
    )->serialize();
}

1;
