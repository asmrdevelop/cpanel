# cpanel - Cpanel/Exception/DirectoryDoesNotExist.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::Exception::DirectoryDoesNotExist;

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

=head1 MODULE

C<Cpanel::Exception::DirectoryDoesNotExist>

=head1 DESCRIPTION

C<Cpanel::Exception::DirectoryDoesNotExist> is used when the a directory that does not
exist on the file system is requested, but does not exist.

=head1 USAGE

=head2 ARGUMENTS

=over

=item dir - string

Required. The directory requested that did not exist.

=back

=head1 SYNOPSIS

  my $dir = '/home/kermit/missing';
  if ( !-d $dir ) {
      die Cpanel::Exception::create(
        'DirectoryDoesNotExist',
        [
            dir => $dir,
        ]);
  }

=cut

sub _default_phrase {
    my ($self) = @_;

    my $directory = $self->get('dir');

    return Cpanel::LocaleString->new(
        'The “[_1]” directory does not exist.',
        $directory,
    );
}

1;
