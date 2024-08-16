
# cpanel - Cpanel/DAV/Calendars.pm                 Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::DAV::Calendars;

use cPstrict;

use Cpanel::DAV::AppProvider ();
use Cpanel::DAV::Result      ();
use Cpanel::DAV::Principal   ();
use Cpanel::Locale::Lazy 'lh';

=head1 NAME

Cpanel::DAV::Calendars

=head1 DESCRIPTION

This module contains method wrappers for various CalDAV calls.

=head1 ASSUMPTIONS

1. The principal has already been created by some other means.

2. This module is running as the user who owns the principal (not as root).

3. We don't know the DAV user's password, nor do we want to rely on cpdavd itself to service
the request.

4. Any path passed in to the module has already been validated based on the privilege
restrictions the caller wants to enforce.

The goal is to circumvent cpdavd and issue a request directly via Cpanel::DAV::CGI.

=head1 FUNCTIONS

=head2 create_calendar

Creates a named calendar for a principal.

Arguments

  - A Cpanel::DAV::Principal
  - String - $path          - file path name of the calendar collection, i.e. /home/user/.caldav/user@domain/tld/$calname/
  - String - $displayname   - "pretty" name of the calendar, i.e. "Calendar"
  - String - $description   - optional description for the calendar, i.e. "Company Meetings."
  - String - $color         - Color of the calendar in hexidecimal format (ex. #FFOOFF )
  - String - $protected     - The calendar is protected (boolean)

=cut

sub create_calendar {    ##no critic(Subroutines::ProhibitManyArgs)
    my ( $principal, $path, $displayname, $description, $color, $protected ) = @_;
    $principal = Cpanel::DAV::Principal::resolve_principal($principal);

    # Setup defaults
    $displayname = lh()->maketext('Calendar') if !$displayname;

    my ( $module, $failed ) = Cpanel::DAV::AppProvider::load_module( 'caldav-carddav', 'calendar' );
    return $failed if $failed;

    # Do not just trust that can() returns a subroutine ref.
    # Do nothing if it does not.
    my $sr = $module->can('create_collection');
    return if ref $sr ne 'CODE';
    my $opts = {
        'displayname'    => $displayname,
        'description'    => $description,
        'calendar-color' => $color,
    };
    $opts->{'protected'} = 1 if $protected;
    return $sr->( $module, $principal, $path, $opts );
}

=head2 get_calendars

Fetches the list of  calendars for a principal.

Arguments

  - A Cpanel::DAV::Principal

=cut

sub get_calendars {
    my ($principal) = @_;
    $principal = Cpanel::DAV::Principal::resolve_principal($principal);

    my $path = get_root_collection_name() . '/' . $principal->name;

    my ( $module, $failed ) = Cpanel::DAV::AppProvider::load_module( 'caldav-carddav', 'calendar' );
    return $failed if $failed;

    my $sr = $module->can('get_collections');
    return if ref $sr ne 'CODE';
    return $sr->( $module, $principal, 'VCALENDAR' );
}

=head2 update_calendar_by_path

Updates the calendar's properties/metadata by path for a principal.

Arguments

  - A Cpanel::DAV::Principal
  - String - path - path in the CalDAV system for the calendar.

=cut

sub update_calendar_by_path {
    my ( $principal, $path, $name, $description, $color ) = @_;
    $principal = Cpanel::DAV::Principal::resolve_principal($principal);

    my ( $module, $failed ) = Cpanel::DAV::AppProvider::load_module( 'caldav-carddav', 'calendar' );
    return $failed if $failed;

    my $sr = $module->can('update_collection');
    return if ref $sr ne 'CODE';
    my $opts = {
        'displayname'    => $name,
        'description'    => $description,
        'calendar-color' => $color,
    };

    # Disallow deletion of the default calendar.
    $opts->{'protected'} = 1 if $path eq 'calendar';
    return $sr->( $module, $principal, $path, $opts );
}

=head2 remove_calendar_by_path

Deletes the calendar by its path for a principal.

Arguments

  - A Cpanel::DAV::Principal
  - String - path - path in the CalDAV system for the calendar.

=cut

sub remove_calendar_by_path {
    my ( $principal, $path ) = @_;
    $principal = Cpanel::DAV::Principal::resolve_principal($principal);

    my $name = $principal->name;
    my $root = get_root_collection_name();

    my ( $module, $failed ) = Cpanel::DAV::AppProvider::load_module( 'caldav-carddav', 'calendar' );
    return $failed if $failed;

    my $sr = $module->can('remove_collection');
    return if ref $sr ne 'CODE';
    return $sr->( $module, $principal, $path );
}

=head2 remove_calendar_by_name

Deletes the named calendar for a principal.

Arguments

  - A Cpanel::DAV::Principal
  - String - name of the calendar

=cut

sub remove_calendar_by_name {
    my ( $principal, $name ) = @_;
    $principal = Cpanel::DAV::Principal::resolve_principal($principal);

    my $path = get_root_collection_name() . '/' . $principal->name . '/' . $name;
    return remove_calendar_by_path( $principal, $path );
}

=head2 remove_all_calendars

Deletes all the calendars for a principal.

Arguments

  - A Cpanel::DAV::Principal
  - Hashref - options - options for the removal any of the following options:
    - Boolean - force - is not provided or false, prevents removal of default calendar. if true, will remove any calendar.

=cut

sub remove_all_calendars {
    my ($principal) = @_;
    $principal = Cpanel::DAV::Principal::resolve_principal($principal);

    my $result = get_calendars($principal);

    if ( !$result ) {
        return Cpanel::DAV::Result->new()->failed(
            0,
            lh()->maketext(
                'The system could not retrieve and remove the calendars for “[_1]”.',
                $principal->name
            )
        );
    }

    if ( !$result->meta->ok ) {
        $result->meta->text(
            lh()->maketext(
                'The system could not remove the calendars for “[_1]”: [_2]',
                $principal->name,
                $result->meta->text
            )
        );
        return $result;
    }

    # Remove each calender
    my $calendars = $result->data;
    my @failed    = ();

    foreach my $calendar (@$calendars) {
        my $response = remove_calendar_by_path( $principal, $calendar->{'path'} );
        if ( !$response->meta->ok ) {
            $calendar->{'error'} = $response->meta->text;
            push @failed, $calendar;
        }
    }

    $result = Cpanel::DAV::Result->new();
    if ( scalar @failed ) {
        $result->failed( 0, lh()->maketext('The system could not remove one or more calendars from your account.'), \@failed );
    }
    else {
        $result->success( 200, lh()->maketext('You have successfully removed all calendars from your account.') );
    }

    return $result;
}

sub get_root_collection_name {
    return '/';
}

1;
