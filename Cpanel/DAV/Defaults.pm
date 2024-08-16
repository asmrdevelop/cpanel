
# cpanel - Cpanel/DAV/Defaults.pm                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::DAV::Defaults;

use strict;
use warnings;

use Cpanel::LoadModule ();

our $SHARED_ADDRESS_BOOK_NAME = 'shared-addressbook';

=head1 NAME

Cpanel::DAV::Defaults

=head1 DESCRIPTION

This module sets up default calendars and address books for principals via CalDAV/CardDAV.

=head1 ASSUMPTIONS

1. The principal has already been created by some other means.

2. This module is running as the user who owns the principal (not as root).

3. We don't know the DAV user's password, nor do we want to rely on cpdavd itself to service
the request.

The goal is to circumvent cpdavd and issue a request directly via Cpanel::DAV::CGI.

=head1 FUNCTIONS

=head2 create_calendar

Creates the default calendar for a principal.

Arguments

  - A Cpanel::DAV::Principal

=cut

sub create_calendar {
    my ($principal) = @_;

    my $path        = 'calendar';
    my $display     = lh()->maketext('cPanel CalDAV Calendar');
    my $description = lh()->maketext('Default Calendar automatically created for your account.');

    # Create the calendar
    Cpanel::LoadModule::load_perl_module('Cpanel::DAV::Calendars');
    return Cpanel::DAV::Calendars::create_calendar( $principal, $path, $display, $description, '#ff6c2c', 1 );
}

=head2 create_addressbook

Creates the default address book for a principal.

Arguments

  - $principal - Cpanel::DAV::Principal | String - optional principal, user or email address.
  - $opts        - HashRef
    - shared         - Boolean - optional if true, then the address book is shared with everyone, otherwise, its private.
    - fail_if_exists - Boolean - if true will fail if it exists. Otherwise it will just return the existing addressbook.

=cut

sub create_addressbook {
    my ( $principal, $opts ) = @_;

    my $path        = 'addressbook';
    my $display     = lh()->maketext('cPanel CardDAV Address Book');
    my $description = lh()->maketext('Default Address Book automatically created for your account.');

    Cpanel::LoadModule::load_perl_module('Cpanel::DAV::AddressBooks');

    # Create the address book
    return Cpanel::DAV::AddressBooks::create_addressbook( $principal, $path, $display, $description, 1 );
}

=head2 create_shared_addressbook

Creates the default address book for a principal.

Arguments

  - $principal - Cpanel::DAV::Principal | String - optional principal, user or email address.
  - $opts        - HashRef
    - shared         - Boolean - optional if true, then the address book is shared with everyone, otherwise, its private.
    - fail_if_exists - Boolean - if true will fail if it exists. Otherwise it will just return the existing addressbook.

=cut

# HBHB TODO - currently not implemented, but maybe in the future
sub create_shared_addressbook {
    my ( $principal, $opts ) = @_;
    $opts = {} if !$opts;
    $opts->{shared} //= 1;

    my $path        = 'shared-addressbook';
    my $display     = lh()->maketext('Shared Address Book');
    my $description = lh()->maketext('All the webmail users under this [asis,cPanel] account can view shared address books.');

    Cpanel::LoadModule::load_perl_module('Cpanel::DAV::AddressBooks');

    # Create the address book
    return Cpanel::DAV::AddressBooks::create_addressbook( $principal, $path, $display, $description, $opts );
}

=head2 remove_webmail_user_calendars_and_address_books

Removes the calendars and address books for the specified webmail account.

This function is only intended for use on email accounts. (cPanel account
cleanup happens when the user's home directory is removed.)

Arguments

  - string - $email      - webmail accounts email address.

=cut

sub remove_webmail_user_calendars_and_address_books {
    my ($email) = @_;

    # Cleanup the CalDAV, CardDAV and related principal data
    require Cpanel::DAV::Principal;
    my $principal = Cpanel::DAV::Principal::resolve_principal($email);

    require Cpanel::DAV::AddressBooks;

    # Clean up any custom user generated address books
    my $resp = Cpanel::DAV::AddressBooks::remove_all_addressbooks( $principal, { force => 1 } );
    if ( !$resp->{'meta'}{'ok'} ) {
        return $resp;
    }

    # Clean up any custom user generated calendars
    require Cpanel::DAV::Calendars;
    $resp = Cpanel::DAV::Calendars::remove_all_calendars( $principal, { force => 1 } );
    if ( !$resp->{'meta'}{'ok'} ) {
        return $resp;
    }

    # HBHB TODO - reimpliment if/when the time comes
    #     $resp = Cpanel::DAV::AddressBooks::remove_user_from_shared_addressbook($principal);
    #     if ( !$resp->{'meta'}{'ok'} ) {
    #         return $resp;
    #     }

    Cpanel::LoadModule::load_perl_module('Cpanel::DAV::Result');
    return Cpanel::DAV::Result->new()->success( 200, lh()->maketext( "The system successfully removed all calendar and address book resources for “[_1]”.", $email ) );
}

my $locale;

sub lh {
    if ( !$locale ) {

        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        $locale = Cpanel::Locale->get_handle();    # If cpdavd ever gets compiled, this will need to be quoted as 'Cpanel::Locale'->get_handle()
    }
    return $locale;
}

1;
