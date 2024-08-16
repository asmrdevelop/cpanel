# cpanel - Cpanel/Validate/UUID.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Validate::UUID;

use cPstrict;

use Cpanel::Exception ();

=head1 MODULE

C<Cpanel::Validate::UUID>

=head1 DESCRIPTION

C<Cpanel::Validate::UUID> provides methods to validate that a string is a valid UUID.
Methods are also provided to die upon failure to produce a standardized error message.

=head1 SYNOPSIS

    require Cpanel::Validate::UUID;
    my $uuid = get_user_input();
    Cpanel::Validate::UUID::validate_uuid_or_die($uuid);

    # If we get here, $uuid is valid
    save_user_data($uuid)

=head1 FUNCTIONS

=head2 is_valid_uuid(VALUE)

=head3 ARGUMENTS

=over

=item VALUE - any

The value to validate as being a UUID string.

=back

=head3 RETURNS

1 when the value is a valid UUID string, 0 otherwise.

=cut

sub is_valid_uuid ( $value, %opts ) {
    return 0 if !defined $value || $value eq '';

    return $value =~ m/^[0-9a-f]{8}-[0-9a-f]{4}-[0-5][0-9a-f]{3}-[089ab][0-9a-f]{3}-[0-9a-f]{12}\z/i ? 1 : 0;
}

=head2 validate_uuid_or_die(VALUE)

Validate that the value is a UUID string or throw an exception.

=head3 ARGUMENTS

=over

=item VALUE - any

The value to validate as being a UUID string.

=item NAME - string

Optional. If provided, the name of the parameter from the callers context.

=back

=head3 THROWS

When the value is not a valid UUID string.

=cut

sub validate_uuid_or_die ( $value, $name = '' ) {
    if ( !is_valid_uuid($value) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [output,acronym,UUID,Universally Unique Identifier] string.' ) if !$name;
        die Cpanel::Exception::create(
            'InvalidParameter',
            'The “[_1]” argument contains the value “[_2]”, which is not a valid [output,acronym,UUID,Universally Unique Identifier] string.',
            [ $name, $value ]
        );
    }

    return 1;
}

1;
