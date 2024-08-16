package Whostmgr::API::1::NVData;

# cpanel - Whostmgr/API/1/NVData.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Logger::Soft ();
use Whostmgr::NVData     ();

use constant NEEDS_ROLE => {
    nvget => undef,
    nvset => undef,
};

my $MAX_STORE_LENGTH   = 128;
my $MAX_KEYNAME_LENGTH = 128;
my $MAX_VALUE_LENGTH   = 2048;

=head1 MODULE

B<Whostmgr::API::1::NVData>

=head1 DESCRIPTION

B<Whostmgr::API::1::NVData> provides remote api access to the name/value data
pairs for each user. These pairs are stored in files for each reseller
and root in /var/cpanel/whm/nvdata. The root user can access any resellers
data by passing a 'store' parameter. Only root can access or modify the data for other
users. This data is intended to store personalization information for
various UI and core components.

It's not recommended to store any security related data in this store.

=head1 FUNCTIONS

=head2 nvget

Fetch a single name/value pair.

=head3 DEPRECATED

Use B<Whostmgr::API::1::personalization_get> instead.

=head3 ARGUMENTS

=over

=item key - String

Name used to lookup the key/value pair. Key names longer than 128 characters are truncated to 128 characters.

=item store - Optional - String

If called by root, can be any name in which to store
the values. Otherwise it is ignored.  The store cannot
be more than 128 characters.

=back

=head3 RETURNS

The following structure:

=over

=item nvdatum - HASH

With the following structure:

=over

=item key STRING

Name of the requested pair.

=item value STRING|UNDEF

The value stored in the name/value pair if it exists. Otherwise, undef
is returned to indicate the name is undefined.

=back

=back

=cut

sub nvget {
    my ( $args, $metadata ) = @_;

    Cpanel::Logger::Soft::deprecated('The [asis,nvget] method is deprecated. Please use [asis,personalization_get] instead.');

    my $key = substr $args->{'key'}, 0, $MAX_KEYNAME_LENGTH;
    if ( !exists $args->{'store'} ) { $args->{'store'} = ''; }
    my $store = substr $args->{'store'}, 0, $MAX_STORE_LENGTH;
    my $value = Whostmgr::NVData::get( $key, $store );
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'nvdatum' => { 'key' => $key, 'value' => [$value] } };
}

=head2 nvset

Sets name/value pairs

=head3 DEPRECATED

Use B<Whostmgr::API::1::personalization_set> instead.

=head3 ARGUMENTS

=over

=item keyS<*> - String

Each parameter with the 'key' prefix is considered
a name to save a key/value pair too. Key names longer
than 128 characters are truncated to 128 characters.

Examples:

keyproperty1
keyproperty2
keypage_size
keylast_seach_text

=item valueS<*> - String

Each parameter with the 'value' prefix is considered
a value to save a key/value pair too. Values longer
than 2048 characters are truncated to 2048 characters.
The value to set is passed in the query string or post
data as follows:

Examples:

valueproperty1=1234
valueproperty2=2345
valuepage_size=20
valuelast_search_text=toaster

=item store - Optional - String

If called by root, can be any name in which to store
the values. Otherwise it is ignored.  The store cannot
be more than 128 characters.

=back

=head3 RETURNS

The following structure:

=over

=item nvdatum - ARRAY of HASH

Where each HASH has the following structure:

=over

=item key STRING

The name of the name/value pair.

=item value STRING

The value stored in the name/value pair.

=back

=back

=cut

sub nvset {
    my ( $args, $metadata ) = @_;

    Cpanel::Logger::Soft::deprecated('The [asis,nvset] method is deprecated. Please use [asis,personalization_set] instead.');

    if ( !exists $args->{'store'} ) { $args->{'store'} = ''; }
    my $store = substr $args->{'store'}, 0, $MAX_STORE_LENGTH;
    my %nvdata;
    foreach my $arg ( keys %$args ) {
        next if $arg !~ m/^key(.*)/;
        my $id = $1;
        $nvdata{ $args->{$arg} } = $args->{ 'value' . $id };
    }

    my $result = 1;
    my $reason;
    my %set_nvdata;
    while ( my ( $key, $value ) = each %nvdata ) {
        $key   = substr $key,   0, $MAX_KEYNAME_LENGTH;
        $value = substr $value, 0, $MAX_VALUE_LENGTH;
        if ( !Whostmgr::NVData::set( $key, $value, $store ) ) {
            my $msg = 'Failed to set value for [' . $key . '].';
            $result = 0;
            $reason = length $reason ? $reason . ' ' . $msg : $msg;
        }
        else {
            $set_nvdata{$key} = { 'key' => $key, 'value' => $value };
        }
    }

    $metadata->{'result'} = $result;
    if ($result) {
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'reason'} = $reason;
    }
    return if !$result;
    return { 'nvdatum' => [ values %set_nvdata ] };
}

1;
