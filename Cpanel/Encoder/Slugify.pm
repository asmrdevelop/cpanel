
# cpanel - Cpanel/Encoder/Slugify.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Encoder::Slugify;

use strict;
use warnings;

=head1 MODULE

C<Cpanel::Encoder::Slugify>

=head1 DESCRIPTION

C<Cpanel::Encoder::Slugify> provides a transformation function that makes a string
safe to use in an HTML id or class attribute.

=head1 FUNCTIONS

=head2 slugify(TEXT, SEPERATOR = '-')

Convert any text into a name that is safe for use in an HTML id/class attribute.

=head3 ARGUMENTS

=over

=item TEXT - string

Text you want to slugify.

=item SEPERATOR - string

String you want to use to replace any unacceptable characters. Defaults to '-'.

=back

=head3 RETURNS

Text that is safe to use in id or class attributes.

=cut

sub slugify {
    my ( $text, $alt ) = @_;
    $alt = '-' if !$alt;
    $text =~ s/[^a-z0-9]+/$alt/gi;               # replace any non-safe character with separator.
    $text =~ s/^(?:$alt)?(.+?)(?:$alt)?$/$1/;    # remove leading or trailing separator
    $text =~ s/(?:$alt){2,}/$alt/;               # reduce multiple separators to single separator.
    $text =~ s/^(.+)$/\L$1/;                     # convert all characters to lowercase.
    return $text;
}

1;
