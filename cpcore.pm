# cpanel - cpcore.pm                               Copyright 2023 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package cpcore;

use strict;
use warnings;

use v5.36;

use constant flag => "cpanel/is_core";

=head1 MODULE

C<cpcore>

=head1 DESCRIPTION

C<cpcore> provides a pragma that can be used to mark modules as part of the Core cPanel system. C<core>
packages must have a perl compatible semantic $VERSION like:

  our $VERSION = '1.0.0';

Over time additional rules about C<core> packages may be enforced.

=head1 SYNOPSIS

  package Cpanel::Primes;

  use strict;
  use warnings;

  use cpcore;
  our $VERSION = '1.0.0';

  ...

  # to determin if we are in a core module you can use
  if (cpcore::is_core()) {
    # the current module is part of the cpanel core system.
  }

  # to determin if the caller is a core module you can use
  my $parent_level = 2;
  if (cpcore::is_core($parent_level)) {
    # the current module is part of the cpanel core system.
  }

  # note you will need to count the stack depth to figure
  # out how many parent levels to use here.

=head1 TODO

=over

=item * Add compile time check to enforce the $VERSION package variable and its format in packages that have C<use cpcore>.

=back

=head1 FUNCTIONS

=head2 import()

Support the C<use cpcore> pragma to mark the package as part of the core system.

=cut

sub import {
    $^H{ flag() } = 1;    ## no critic (Variables::RequireLocalizedPunctuationVars)
    return 1;
}

=head2 unimport()

Support the C<no cpcore> mostly for sanity checking.

=cut

sub unimport {
    $^H{ flag() } = 0;    ## no critic (Variables::RequireLocalizedPunctuationVars)
    return 1;
}

=head2 is_core($level)

Check if the code is running in a core cpanel module.

=head3 ARGUMENTS

=over

=item $level - number

How many levels up in the stack to look. Defaults to 0.

=back

=head3 RETURNS

True value when the package is a cPanel Core module. Returns false otherwise.

=cut

sub is_core {
    my $level    = shift // 0;
    my $hinthash = ( caller($level) )[10];
    return $hinthash->{ flag() };
}

1;
