
# cpanel - Cpanel/DAV/AppProvider.pm               Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::DAV::AppProvider;

use cPstrict;

use Try::Tiny;

use Cpanel::DAV::Result ();
use Cpanel::LoadModule  ();
use Cpanel::Locale::Lazy 'lh';

=head1 NAME

Cpanel::DAV::AppProvider

=head1 DESCRIPTION

This module contains code to identify the correct cardDAV/calDAV application to run based on configuration.

=head1 FUNCTIONS

=head2 get_application

Fetches the current concrete application mapping to the abstract application requested.

Arguments

$app - string - application service being requested

=cut

sub get_application {
    my ($app) = @_;

    if ( $app eq 'caldav-carddav' ) {
        if ( !_touch_folder_exists('/var/cpanel/dav-provider/') ) {
            return 'caldav-carddav-cpdavd';
        }
        else {
            return 'caldav-carddav-cpdavd' if _touch_exists('/var/cpanel/dav-provider/use-cpdavd');

            # Any other implementions go here...
            return 'caldav-carddav-cpdavd';    # Safe fallback
        }
    }
    return $app;
}

=head2 get_implementation_module_name

Fetches the module implementing the specific feature.

Arguments

$app     - string - application service being requested
$feature - string - feature being requested

Returns

String - Perl name of the module implementing the feature.

=cut

sub get_implementation_module_name {
    my ( $app, $feature ) = @_;
    my $app_impl = get_application($app);
    if ( $app_impl eq 'caldav-carddav-cpdavd' ) {
        if ( $feature eq 'calendar' ) {
            return 'Cpanel::DAV::Backend::CPDAVDCalendar';
        }
        elsif ( $feature eq 'addressbook' ) {
            return 'Cpanel::DAV::Backend::CPDAVDAddressBook';
        }
    }
    return;
}

=head2 load_module

Loads and returns the module for the app/feature.

Arguments

  $app     - string - application service being requested
  $feature - string - feature being requested

Returns

  List of:
    a string containing the name of the module | undef,
    empty string | Cpanel::DAV::Result

=cut

sub load_module {
    my ( $app, $feature ) = @_;

    my $module = get_implementation_module_name( $app, $feature );
    my @exception_return;
    try {
        Cpanel::LoadModule::load_perl_module($module);
    }
    catch {
        @exception_return = ( '', Cpanel::DAV::Result->new()->failed( 500, lh()->maketext( 'The system could not load the module: [_1]', $module ) ) );
    };

    return @exception_return if @exception_return;
    return ($module);
}

sub _touch_folder_exists {
    my ($path) = @_;
    return ( -d $path ? 1 : 0 ) if $path;
    return 0;
}

sub _touch_exists {
    my ($path) = @_;
    return ( -e $path ? 1 : 0 ) if $path;
    return 0;
}

1;
