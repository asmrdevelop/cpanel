package Cpanel::Exception::InvalidParameter;

# cpanel - Cpanel/Exception/InvalidParameter.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::InvalidParameter - “What you gave me doesn’t work.”

=head1 SYNOPSIS

    die Cpanel::Exception::create('InvalidParameter', 'That’s not good enough. (Here’s why: ..)');  ## no extract maketext

=head1 DESCRIPTION

This class represents a generic rejection of a given input. It neither
provides a default message nor recognizes any parameters.

Don’t use this for I<missing> inputs; for that use
L<Cpanel::Exception::MissingParameter>.

This class extends L<Cpanel::Exception>.

=head1 SEE ALSO

=over

=item * L<Cpanel::Exception::Empty>

=item * L<Cpanel::Exception::MissingParameter>

=back

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Exception );

1;
