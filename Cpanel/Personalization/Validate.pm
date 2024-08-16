
# cpanel - Cpanel/Personalization/Validate.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Personalization::Validate;

use strict;
use warnings;

my $MAX_STORE_LENGTH   = 128;     # This limit is defined to prevent file names from exceeding the max filename length for the filesystem. Space is reserved to the user being appended. The actual limits on the supported file systems is 255, so we are reserving 127 bytes for the user. (WHM)
my $MAX_KEYNAME_LENGTH = 128;     # This limit is defined to prevent file names from exceeding the max filename length for the filesystem. Space is reserved to the user being appended. The actual limits on the supported file systems is 255, so we are reserving 127 bytes for the user. (CPANEL)
my $MAX_VALUE_LENGTH   = 2048;    # This limit is arbitrary, but prevents data stored in nvdata files from filling up the users quota or the entire file system.

=head1 MODULE

C<Cpanel::Personalization::Validate>

=head1 DESCRIPTION

C<Cpanel::Personalization::Validate> provides various validation routines for the
Cpanel::API::Personalization and Whostmgr::API::1::Personalization.

=head1 FUNCTIONS

=head2 validate_names(NAMES)

Validates the names passed to the getter method

=head3 ARGUMENTS

=over

=item NAMES - ARRAY of STRING

The list of names to retrieve from the backing store

=back

=head3 THROWS

=over

=item When an empty list is passed

=item When any name in the list exceeds the maximum allowed length

=back

=cut

sub validate_names {
    my @names = @_;
    if ( !scalar @names ) {
        die "You must provide at least one personalization property name to fetch.";
    }

    foreach my $name (@names) {
        if ( ref $name ) {
            die sprintf( 'Name %s is an invalid type. It must be a string', $name );
        }

        if ( length($name) > $MAX_KEYNAME_LENGTH ) {
            die sprintf( 'Name %s is invalid. Names can only be %d characters.', $name, $MAX_KEYNAME_LENGTH );
        }
    }
    return;
}

=head2 validate_object(SETTER_OBJECT)

Validates the structure of the B<SETTER_OBJECT>

=head3 ARGUMENTS

=over

=item SETTER_OBJECT - ANY

=back

=head3 THROWS

=over

=item When the argument is not a HASHREF

=item When there are no keys in the personalization HASHREF child of the object.

=item When any name exceeds the maximum length allowed.

=item When any value exceeds the maximum length allowed.

=back

=cut

sub validate_object {
    my $request = shift;
    if ( !$request || ref $request ne 'HASH' ) {
        die << "        END";
        The request must be an object similar to this example. It must contain a personalization property which is a hash where the name of each property is any valid name and the value is any valid JSON serializable type.

            {
                personalization: {
                    name_1: value_1,
                    ...,
                    name_n: value_n
                }
            }
        END
    }

    my @names = sort keys %{$request};
    if ( !@names ) {
        die "The personalization property must be an object which contains one or more name/value pairs.";
    }

    foreach my $name (@names) {
        if ( length($name) > $MAX_KEYNAME_LENGTH ) {
            die sprintf( 'Name %s is invalid. Names can only be %d characters.', $name, $MAX_KEYNAME_LENGTH );
        }

        my $value = $request->{$name};
        if ( defined $value && length($value) > $MAX_VALUE_LENGTH ) {
            die "Value '$value' is invalid. Values can only be $MAX_VALUE_LENGTH characters.";
        }
    }
    return;
}

=head2 validate_store(STORE)

Validates the B<STORE>. Note the B<STORE> is optional since it will
automatically default to the users name.

=head3 ARGUMENTS

=over

=item STORE - ANY

=back

=head3 THROWS

=over

=item When the store exceeds the maximum length allowed.

=back

=cut

sub validate_store {
    my $store = shift;
    if ( $store && length($store) > $MAX_STORE_LENGTH ) {
        die "Store '$store' is invalid. Stores can only be $MAX_STORE_LENGTH characters.";
    }
    return;
}

=head2 validate_appname()

Validates that the B<$Cpanel::appname> is correctly set in the calling process

=head3 THROWS

=over

=item When the B<$Cpanel::appname> is not set.

=back

=cut

sub validate_appname {
    if ( !$Cpanel::appname ) {
        die '$Cpanel::appname must be set to call this method.';
    }
    return;
}

=head2 validate_authuser()

Validates that the B<$Cpanel::authuser> is correctly set in the calling process

=head3 THROWS

=over

=item When the B<$Cpanel::authuser> is not set.

=back

=cut

sub validate_authuser {
    if ( !$Cpanel::authuser ) {
        die '$Cpanel::authuser must be set when calling this method from webmail.';
    }
    return;
}

1;
