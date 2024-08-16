
# cpanel - Cpanel/Template/Plugin/FilePermissions.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Template::Plugin::FilePermissions;

use strict;
use warnings;

use base 'Template::Plugin';

use Cpanel::FileUtils::Permissions::String ();

=head1 MODULE

C<Cpanel::Template::Plugin::FilePermissions>

=head1 DESCRIPTION

C<Cpanel::Template::Plugin::FilePermissions> provides helpers to build
Unix file permissions represented as octal strings.

=head1 SYNOPSIS

  USE FilePermissions;
  SET oct_bits = bits2oct(user_read => 1);
  # oct_bits == '400'
  SET oct_str = str2oct('r--------');
  # oct_str == '400'

=head1 FUNCTIONS

=head2 load(CLASS, CONTEXT)

Loads the plugin methods into the stash

=head3 ARGUMENTS

=over

=item CLASS

Class of the plugin.

=item CONTEXT - Template::Context

Context from the template processor.

=back

=cut

sub load {
    my ( $class, $context ) = @_;

    my $stash = $context->stash();
    @{$stash}{
        'bits2oct',
        'str2oct',
      } = (
        \&Cpanel::FileUtils::Permissions::String::bits2oct,
        \&Cpanel::FileUtils::Permissions::String::str2oct,
      );

    return $class->SUPER::load($context);
}

1;
