
# cpanel - Cpanel/DAV/AddressBooks.pm              Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::DAV::AddressBooks;

use cPstrict;

use Cpanel::DAV::AppProvider ();
use Cpanel::DAV::Principal   ();
use Cpanel::DAV::Result      ();
use Cpanel::Locale::Lazy 'lh';

=head1 NAME

Cpanel::DAV::AddressBooks

=head1 DESCRIPTION

This module contains method wrappers for various CardDAV calls.

=head1 ASSUMPTIONS

1. The principal has already been created by some other means.

2. This module is running as the user who owns the principal (not as root).

3. We don't know the DAV user's password, nor do we want to rely on cpdavd itself to service
the request.

4. Any path passed in to the module has already been validated based on the privilege
restrictions the caller wants to enforce.

=head1 FUNCTIONS

=head2 create_addressbook

Creates a named address book for a principal.

Arguments

=over

=item -

principal   - Cpanel::DAV::Principal | String - optional principal, user or email address.

=item -

path        - String - file path name of the addressbook, i.e. /home/user/.caldav/user@domain.tld/$path/

=item -

opts        - Hash

=over

=item -

fail_if_exists - Boolean - if true will fail if it exists. Otherwise it will just return the existing addressbook.

=back

=back

Returns

This function returns a Cpanel::DAV::Result object indicating whether the operation succeded
and containing any relevant message about the outcome.

=cut

sub create_addressbook {
    my ( $principal, $path, $displayname, $description, $protected ) = @_;
    $principal = Cpanel::DAV::Principal::resolve_principal($principal);

    my ( $module, $failed ) = Cpanel::DAV::AppProvider::load_module( 'caldav-carddav', 'addressbook' );
    return $failed if $failed;

    my $opts = {
        'displayname' => $displayname,
        'description' => $description,
    };
    $opts->{'protected'} = 1 if $protected;
    return $module->can('create_collection')->( $module, $principal, $path, $opts );
}

=head2 get_addressbooks

Fetches the list of address books for a principal.

Arguments

=over

=item -

principal - Cpanel::DAV::Principal | String

=back

Returns

This function returns a Cpanel::DAV::Result object indicating whether the operation succeded
and containing any relevant message about the outcome.

=cut

sub get_addressbooks {
    my ($principal) = @_;
    $principal = Cpanel::DAV::Principal::resolve_principal($principal);
    my ( $module, $failed ) = Cpanel::DAV::AppProvider::load_module( 'caldav-carddav', 'addressbook' );

    return $failed if $failed;

    return $module->can('get_collections')->( $module, $principal, 'VADDRESSBOOK' );
}

=head2 update_addressbook_by_path

Updates the calendar's properties/metadata by path for a principal.

Arguments

  - A Cpanel::DAV::Principal
  - String - path - path in the CalDAV system for the addressbook.
  - String - name - The name to give the updated addressbook
  - String - description - The description to give the updated addressbook

=cut

sub update_addressbook_by_path {
    my ( $principal, $path, $name, $description ) = @_;
    $principal = Cpanel::DAV::Principal::resolve_principal($principal);

    my ( $module, $failed ) = Cpanel::DAV::AppProvider::load_module( 'caldav-carddav', 'addressbook' );
    return $failed if $failed;

    my $sr = $module->can('update_collection');
    return if ref $sr ne 'CODE';

    my $opts = {
        'displayname' => $name,
        'description' => $description,
    };
    return $sr->( $module, $principal, $path, $opts );
}

=head2 remove_addressbook_by_path

Deletes the address book by its path for a principal.

Arguments

=over

=item -

A Cpanel::DAV::Principal

=item -

String - path - path in the CardDAV system for the address book.

=back

Returns

This function returns a Cpanel::DAV::Result object indicating whether the operation succeded
and containing any relevant message about the outcome.

=cut

sub remove_addressbook_by_path {
    my ( $principal, $path ) = @_;
    $principal = Cpanel::DAV::Principal::resolve_principal($principal);

    my $name = $principal->name;

    my ( $module, $failed ) = Cpanel::DAV::AppProvider::load_module( 'caldav-carddav', 'addressbook' );
    return $failed if $failed;

    return $module->can('remove_collection')->( $module, $principal, $path );
}

=head2 remove_addressbook_by_name

Deletes the named address book for a principal.

Arguments

=over

=item -

principal - A Cpanel::DAV::Principal

=item -

name      - String - name of the address book

=back

Returns

This function returns a Cpanel::DAV::Result object indicating whether the operation succeded
and containing any relevant message about the outcome.


=cut

sub remove_addressbook_by_name {
    my ( $principal, $name, ) = @_;
    $principal = Cpanel::DAV::Principal::resolve_principal($principal);

    my $path = _get_root_collection_name() . '/' . $principal->name . '/' . $name;
    return remove_addressbook_by_path( $principal, $path );
}

=head2 remove_all_addressbooks

Deletes all the address books for a principal.

Arguments

=over

=item -

principal - A Cpanel::DAV::Principal

=item -

opts      - Hashref - options for the removal any of the following options:

=over

=item -

force      - Boolean - is not provided or false, prevents removal of default address book. if true, will remove any address book.

=back

=back

Returns

This function returns a Cpanel::DAV::Result object indicating whether the operation succeded
and containing any relevant message about the outcome.

=cut

sub remove_all_addressbooks {
    my ( $principal, $opts ) = @_;

    my $result = get_addressbooks($principal);
    if ( !$result ) {
        return Cpanel::DAV::Result->new()->failed(
            0,
            lh()->maketext( 'The system could not retrieve and remove all address books for “[_1]”.', $principal->name )
        );
    }

    if ( !$result->meta->ok ) {
        $result->meta->text(
            lh()->maketext(
                'The system could not remove the address books for “[_1]”: [_2]',
                $principal->name,
                $result->meta->text
            )
        );
        return $result;
    }

    # Remove each address book
    my $addressbooks = $result->data;
    my @failed       = ();

    foreach my $addressbook (@$addressbooks) {
        my $response = remove_addressbook_by_path( $principal, $addressbook->{'path'}, $opts );
        if ( !$response->meta->ok ) {
            $addressbook->{'error'} = $response->meta->text;
            push @failed, $addressbook;
        }
    }

    $result = Cpanel::DAV::Result->new();
    if ( scalar @failed ) {
        $result->failed( 0, lh()->maketext('The system could not remove one or more address books from your account.'), \@failed );
    }
    else {
        $result->success( 200, lh()->maketext('You have successfully removed all address books from your account.') );
    }

    return $result;
}

# HBHB TODO - path for this ?
sub _get_root_collection_name {
    return '/addressbooks';
}

1;
