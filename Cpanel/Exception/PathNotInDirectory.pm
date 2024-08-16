package Cpanel::Exception::PathNotInDirectory;

# cpanel - Cpanel/Exception/PathNotInDirectory.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LocaleString ();

use parent qw( Cpanel::Exception );

=head1 MODULE

C<Cpanel::Exception::PathNotInDirectory>

=head1 PARENT

C<Cpanel::Exception>

=head1 DESCRIPTION

C<Cpanel::Exception::PathNotInDirectory> exception class. Use this
when you have a path that is expected to be contained in a specific
parent directory, but the path has a different parent.

=head1 FUNCTIONS

=head2 INSTANCE->_default_phrase()

Override to generate the default phrase for the exception.

=head3 ARGUMENTS

Arguments are retrieved via the $self->get() helper.

=over

=item path - string

Required. A path on the file system.

=item base - string

Required. The base path the C<path> must belong to.

=back

=cut

#Named parameters:
#
#   path  - required, string
#   base  - required, string
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        '“[_1]” path is not in the directory “[_2]”.',
        $self->get('path'),
        $self->get('base'),
    );
}
1;
