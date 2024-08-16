# cpanel - Cpanel/Validate/Ascii.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Validate::Ascii;

use cPstrict;

use Cpanel::Exception ();

=head1 MODULE

C<Cpanel::Validate::Ascii>

=head1 DESCRIPTION

C<Cpanel::Validate::Ascii> provides methods to validate that a string contains valid ASCII characters. Methods can
optionally limit checks to only printable characters. Methods are also provided to die upon failure to produce a standardized error message.

=head1 SYNOPSIS

    require Cpanel::Validate::Ascii;
    my $authname = get_user_input();
    Cpanel::Validate::Ascii::validate_ascii_or_die( $authname, 'authname', print_only => 1 );

    # If we get here, $authname is valid
    save_user_data($authname)

    # ...

    is Cpanel::Validate::Ascii::is_valid_ascii( $char, print_only => 1 ), 1, "$char ($_) is valid printable ascii";

=head1 FUNCTIONS

=head2 is_valid_ascii(VALUE)

=head3 ARGUMENTS

=over

=item VALUE - any

The value to check if its ASCII.

=item OPTS - hash

=over

=item print_only - Boolean

Defaults to false. When true it will only be valid if all the characters are printable. It does not include the control characters.

=back

=back

=head3 RETURNS

1 when the value is only ASCII characters, 0 otherwise.

=cut

sub is_valid_ascii ( $value, %opts ) {
    %opts = ( print_only => 0 ) if !keys %opts;
    return 1                    if !defined $value || $value eq '';    # Assume empty is ok.

    return $value =~ m/[^\x20-\x7E]/ ? 0 : 1 if $opts{print_only};
    return $value =~ m/[^\x00-\x7F]/ ? 0 : 1;
}

=head2 validate_ascii_or_die(VALUE, NAME, OPTS)

Validate that the characters in the value are in the standard ASCII character set.

=head3 ARGUMENTS

=over

=item VALUE - any

=item NAME - string

Optional, if provided, the name of the parameter from the callers context.

=item OPTS - hash

=over

=item print_only - Boolean

Defaults to false. When true will only be valid if all the characters printable. Does not include the control characters.

=back

=back

=head3 THROWS

When the value is not valid.

=cut

sub validate_ascii_or_die ( $value, $name = '', %opts ) {
    if ( !is_valid_ascii( $value, %opts ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” contains unsupported characters. It must contain only common letters, numbers, or punctuation characters.' ) if !$name;
        die Cpanel::Exception::create(
            'InvalidParameter',
            'The “[_1]” argument contains the value “[_2]”, which contains unsupported characters. It must contain only printable [output,acronym,ASCII,American Standard Code for Information Interchange] characters.',
            [ $name, $value ]
        );
    }

    return 1;
}

1;
