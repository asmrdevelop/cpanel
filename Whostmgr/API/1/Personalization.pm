package Whostmgr::API::1::Personalization;

# cpanel - Whostmgr/API/1/Personalization.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Personalization::Validate ();
use Whostmgr::NVData                  ();

use constant NEEDS_ROLE => {
    personalization_get => undef,
    personalization_set => undef,
};

use Cpanel::Imports;

=head1 MODULE

C<Whostmgr::API::1::Personalization>

=head1 DESCRIPTION

C<Whostmgr::API::1::Personalization> provides remote API access to the name/value
data pairs for each user. These pairs are stored in files for each reseller
and root in /var/cpanel/whm/nvdata. The root user can access any resellers
data by passing a 'store' parameter. Only root can access or modify the data for
other users. This data is intended to store personalization information for
various UI and core components.

It's not recommended to store any security related data in this store.

=head1 FUNCTIONS

=head2 personalization_get

Gets name/value pairs in a way where the data returned is compatible
with the the similar UAPI C<Cpanel::API::Personalization::get> method.

It's recommended that new code use this method instead of nvget.

=head3 ARGUMENTS

=over

=item names - Array

List of one or more names in an array.

Note: Because this method uses structured data for its input, it may only
be called using a JSON request.

=item store - Optional - String

If called by root, can be any name in which to store
the values. Otherwise it is ignored. The store cannot be more
than 128 characters.

=back

=head3 RETURNS

The following structure:

=over

=item personalization - Hash

Where each key/value pair has the following characteristics:

=over

=item Key:

Named after the field being set

=item Value:

A hash with the following structure:

=over

=item name - String

The name of the field

=item value - String|undef

The value stored in the field or undef if the pair is not available in the store.

=item success - Boolean

True if the value was successfully retrieved; false if the value could not be retrieved for any
reason (including not having been set yet)

=item reason - String

When the C<success> field is false, this field should contain a message indicating what exactly failed.

=back

=back

=back

=head3 THROWS

This function throws an exception and will produce an API error if the key name
exceeds the maximum of 128 characters.

=cut

sub personalization_get {
    my ( $args, $metadata ) = @_;
    my @nvdata;
    my $store = $args->{'store'};
    Cpanel::Personalization::Validate::validate_store($store);

    my @names = @{ $args->{'names'} };
    Cpanel::Personalization::Validate::validate_names(@names);

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    my $many = Whostmgr::NVData::get_many( \@names, $store );
    return { 'personalization' => $many };
}

=head2 personalization_set

Sets name/value pairs in a way where the data returned is compatible
with the the similar UAPI C<Cpanel::API::Personalization::set> method.

It's recommended that new code use this method instead of nvset.

=head3 ARGUMENTS

=over

=item personalization - Hash

A set of key/value pairs representing the names and values to update.
Values are limited to 2048 characters.

If a name that already has a value is not included in this set, it will
be left as-is. The ability to force the set of names and values to exactly
match those specified may be added at a later time.

Note: Because this method uses structured data for its input, it may only
be called using a JSON request.

=item store - Optional - String

If called by root, can be any name in which to store
the values. Otherwise, it is ignored. The store cannot be more
than 128 characters.

=back

=head3 RETURNS

The following structure:

=over

=item personalization - Hash

Where each key/value pair has the following characteristics:

=over

=item Key:

Named after the field being set

=item Value:

A hash with the following structure:

=over

=item name - String

The name of the field

=item value - String|undef

The value stored in the field or undef if the pair is not available in the store.

=item success - Boolean

True if the value was successfully changed on the server side; false if the value could not be
changed. Unlike with failures in C<personalization_get> which could arise simply from nonexistence,
any failure in C<personalization_set> represents a more serious problem that may need attention
(like an out of disk condition).

=item reason - String

When the C<success> field is false, this field should contain a message indicating what exactly failed.

=back

=back

=back

=head3 THROWS

This function throws an exception and will produce an API error if the key name
is not a valid string or exceeds the maximum of 128 characters.  Exceptions are thrown
for values that exceed 2048 characters.

=cut

sub personalization_set {
    my ( $args, $metadata ) = @_;
    my $store = $args->{'store'};
    Cpanel::Personalization::Validate::validate_store($store);

    my $personalization = $args->{personalization};
    Cpanel::Personalization::Validate::validate_object($personalization);

    my @reason;
    my %pairs;
    foreach my $name ( sort keys %{$personalization} ) {
        my $value           = $personalization->{$name};
        my $write_succeeded = eval { Whostmgr::NVData::set( $name, $value, $store ) };
        my $exception       = $@ || locale()->maketext('The system failed to write the [asis,Personalization] datastore.');

        $pairs{$name} = {
            value   => $write_succeeded ? $value : undef,        # FIXME: Would be better to return the original, unchanged value, if the set fails
            success => $write_succeeded ? 1      : 0,
            reason  => $write_succeeded ? 'OK'   : $exception,
        };
    }

    $metadata->{'result'} = 1;      # By design, this always reports success even if something failed
    $metadata->{'reason'} = 'OK';
    return { 'personalization' => \%pairs };
}

1;
