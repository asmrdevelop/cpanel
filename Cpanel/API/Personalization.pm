
# cpanel - Cpanel/API/Personalization.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::API::Personalization;

use strict;
use warnings;

use Cpanel::NVData                    ();
use Cpanel::Personalization::Validate ();

#--------------------------------------------------------------------------
# DEVELOPER NOTES:
#--------------------------------------------------------------------------
# 2) Consider changing the validators to throw Cpanel::Exception classes?
#--------------------------------------------------------------------------

my $requires_json_allow_demo = { requires_json => 1, allow_demo => 1 };

our %API = (
    get => $requires_json_allow_demo,
    set => $requires_json_allow_demo,
);

=head1 MODULE

C<Cpanel::API::Personalization>

=head1 DESCRIPTION

C<Cpanel::API::Personalization> provides remote API access to the name/value
data pairs for the current cPanel user. These pairs are stored in files for
each cPanel user /home/<user>/.cpanel/nvdata/. Each pair is stored in
it own file where the filename is the name of the property.  For webmail users,
the name requested is automatically prefixed with their AUTHUSER which looks
like an email address.

This data is intended to store non-transient personalization preferences
for various UI and core components.

It is not recommended to store any security related data in this store.

=head1 FUNCTIONS

=head2 get

Gets name/value pairs in a way where the data returned is compatible with the
similar method from WHM API 1: C<Whostmgr::API::1::Personalization::personalization_get>

It's recommended that new code use this method instead of other modules
and methods for retrieving nvdata

=head3 ARGUMENTS

=over

=item names - Array

List of one or more names in an array.

Note: Because this method uses structured data for its input, it may only
be called using JSON and POST for a remote request or using the Perl bindings.

=back

=head3 RETURNS

The following structure:

=over

=item personalization - HashRef

Where each key is the name of a requested name/value pair and reference
a HashRef with the following properties:

=over

=item value - String|undef

Value stored in the pair or undef if the pair is not available.

=item success - Boolean (1|0)

1 if the lookup is a success. 0 otherwise.

=item reason - String

If success is 0, this will be the reason for the failure reported by
the underlying system.

=back

=back

=head3 THROWS

This function throws an exception and will produce an API error if
any key name exceeds the maximum of 128 characters.

=cut

sub get {
    my ( $args, $results ) = @_;
    my @nvdata;

    my $prefix = _get_prefix();
    my @names  = @{ $args->get_required('names') };
    Cpanel::Personalization::Validate::validate_names(@names);

    my $pairs = {};
    foreach my $name (@names) {
        my $value;
        eval { $value = Cpanel::NVData::_get( $prefix . $name ); };
        my $exception = $@;
        $pairs->{$name} = {
            value   => $value,
            success => $exception ? 0 : 1,
            reason  => $exception || 'OK',
        };

    }

    $results->data( { personalization => $pairs } );

    return 1;
}

=head2 set

Sets name/value pairs in a way where the data returned is compatible
with the the similar WHM API 1: C<Whostmgr::API::1::Personalization::personalization_set> method.

It's recommended that new code use this method instead of nvset.

=head3 ARGUMENTS

=over

=item personalization - Hash

A set of key/value pairs representing the names and values to update.
Values are limited to 2048 characters.

If a name that already has a value is not included in this set, it will
be left as-is.

Note: Because this method uses structured data for its input, it may only
be called using a JSON POST remote request or directly via the Perl bindings.

=back

=head3 RETURNS

The following Hash Ref:

=over

=item personalization - HashRef

Where each key is the name of a requested name/value pair and reference
a HashRef with the following properties:

=over

=item value - String|undef

Value stored in the pair or undef if the pair is not available.

=item success - Boolean (1|0)

1 if the lookup is a success. 0 otherwise.

=item reason - String

If success is 0, this will be the reason for the failure reported by
the underlying system.

=back

=back

=head3 THROWS

This function throws an exception and will produce an API error if the key name
is not a valid string or exceeds the maximum of 128 characters.  Exceptions are thrown
for values that exceed 2048 characters.

=cut

sub set {
    my ( $args, $results ) = @_;

    my $prefix          = _get_prefix();
    my $personalization = $args->get_required('personalization');
    Cpanel::Personalization::Validate::validate_object($personalization);

    my @names = sort keys %{$personalization};
    my $pairs = {};
    foreach my $name (@names) {
        my $value       = $personalization->{$name} || '';
        my $usecache    = 0;
        my ($exception) = Cpanel::NVData::_set( $prefix . $name, $value, $usecache ) || ('');

        $pairs->{$name} = {
            value   => $value,
            success => $exception ? 0                                                : 1,
            reason  => $exception ? "Failed to set value for $name with: $exception" : 'OK',
        };
    }

    $results->data( { personalization => $pairs } );

    return 1;
}

# Helper method to generate the correct prefix
sub _get_prefix {
    my $prefix = '';
    Cpanel::Personalization::Validate::validate_appname();
    if ( $Cpanel::appname eq 'webmail' ) {
        Cpanel::Personalization::Validate::validate_authuser();
        $prefix = $Cpanel::authuser . '_';
    }
    return $prefix;
}

1;
