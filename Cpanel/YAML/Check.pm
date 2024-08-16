
# cpanel - Cpanel/YAML/Check.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::YAML::Check;

use strict;
use warnings;

use Cpanel::YAML::Syck ();

use Cpanel::Imports;

=head1 MODULE

C<Cpanel::YAML::Check>

=head1 DESCRIPTION

C<Cpanel::YAML::Check> provides helpers to validate if a buffer contains YAML content.

=head1 SYNOPSIS

  use Cpanel::YAML::Check;

=head1 FUNCTIONS

=head2 is_yaml(BUFFER)

Checks if the content of the buffer is YAML.

=head3 ARGUMENTS

=over

=item BUFFER - string | string ref

Verify if the content of the buffer is YAML formatted.

=back

=head3 RETURNS

1 if the buffer can be parsed by YAML::Syck::Load, 0 otherwise.

=head3 THROWS

=over

=item When the buffer is not defined.

=back

=cut

sub is_yaml {
    my ($buffer) = @_;

    die locale()->maketext('You must provide a buffer or a buffer reference.') if !defined $buffer || ( ref $buffer && ref $buffer ne 'SCALAR' );

    my $is_yaml = 0;
    eval {
        ## suppress error output while determining if is YAML
        local $SIG{'__DIE__'};
        YAML::Syck::Load( ref $buffer eq 'SCALAR' ? $$buffer : $buffer );
        $is_yaml = 1;
    };
    return $is_yaml;
}

=head2 is_yaml_or_die(BUFFER)

Dies if the content of the buffer is not YAML.

=head3 ARGUMENTS

=over

=item BUFFER - string

Verify if the content of the buffer is YAML formatted.

=back

=head3 THROWS

=over

=item When the buffer is not defined.

=item When the buffer does not contain YAML content.

=back

=cut

sub is_yaml_or_die {
    my ($buffer) = @_;
    die locale()->maketext('The buffer is not valid [asis,YAML].') if !is_yaml($buffer);
    return;
}

1;
