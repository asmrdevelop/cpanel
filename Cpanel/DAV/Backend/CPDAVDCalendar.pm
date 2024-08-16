
# cpanel - Cpanel/DAV/Backend/CPDAVDCalendar.pm    Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::DAV::Backend::CPDAVDCalendar;

use cPstrict;

use parent qw(Cpanel::DAV::Backend::CPDAVDCollectionBase);

sub _collection_type        { return "VCALENDAR" }
sub _collection_type_pretty { return "calendar" }
sub _valid_meta_keys        { return qw(displayname description type calendar-color protected) }

=head1 NAME

Cpanel::DAV::Backend::CPDAVDCalendar

=head1 DESCRIPTION

Cpanel::DAV::Backend::CPDAVDCalendar

A backend class that can be loaded to handle base tasks for cpdavd,
such as creating a calendar.

=cut

1;
