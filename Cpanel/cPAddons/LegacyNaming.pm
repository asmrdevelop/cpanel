
# cpanel - Cpanel/cPAddons/LegacyNaming.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::LegacyNaming;

use strict;
use warnings;

use Cpanel::cPAddons::Class ();

=head1 NAME

Cpanel::cPAddons::LegacyNaming

=head1 DESCRIPTION

Handles cPAddon name adjustments to account for collisions between
legacy addons and newer RPM-provided addons.

The two adjustments are:

1. An RPM-provided cPAddon will have its name adjusted to match the one
specified by the RPM itself rather than the name of the .pm file
installed by the RPM.

2. A legacy cPAddon will have " (legacy)" added to its name if there is
an RPM that provides the same app.

=cut

our (
    %rpm_provided_module_name_to_app_name,
    %app_name_to_rpm_provided_module_name,
    $cache_ready
);

sub _init {
    if ( !$cache_ready++ ) {

        my $class_obj                   = $Cpanel::cPAddons::Class::SINGLETON ||= Cpanel::cPAddons::Class->new();
        my $rpm_provided_modules        = $class_obj->get_rpm_packaged_modules();
        my @sorted_rpm_provided_modules = sort { $a->{module} cmp $b->{module} } @{$rpm_provided_modules};

        %rpm_provided_module_name_to_app_name = map { $_->{module}                              => $_->{display_app_name} } @sorted_rpm_provided_modules;
        %app_name_to_rpm_provided_module_name = map { $rpm_provided_module_name_to_app_name{$_} => $_ } sort keys %rpm_provided_module_name_to_app_name;
    }

    return;
}

=head1 FUNCTIONS

=head2 get_app_name(MOD)

Given a cPAddons module name, looks up the correct app name to go with it.
In the past, this was as simple as splitting the module name into three
pieces and grabbing the third piece. However, with the addition of RPM-based
cPAddons, there are now some additional rules applied to determining the
app name. See the module description above for details.

=head3 Arguments

MOD - String - The cPAddons module name. See B<perldoc Cpanel::cPAddons::Module>
for more information on cPAddons module names.

=head3 Returns

This function returns a string that is to be used as the app name
for display to the user. This name should not be used as a key for
any sort of data lookups, as it is for human benefit only. If you
want a reliable key to use in data structures, consider using the
full module name (MOD) instead.

=head3 Throws

This function throws an exception if the provided module name doesn't
fit the expected pattern.

=cut

sub get_app_name {
    my ($mod) = @_;

    _init();

    my ( undef, undef, $app ) = split /::/, $mod;
    if ( !$app ) {
        require Carp;    # Defer loading carp since we do not want to perlcc it in since we only call it on error
        Carp::croak("Could not find app name in module name “$mod”");
    }

    # If this module isn't from an RPM, but its app name is also provided by an RPM, mark it as "legacy".
    # Example: WordPress -> WordPress (legacy)
    if ( !$rpm_provided_module_name_to_app_name{$mod} && $app_name_to_rpm_provided_module_name{$app} ) {
        return "$app (legacy)";
    }

    # If this module is provided by an RPM, use the app name from the RPM rather than the name of the .pm file.
    # Example: WordPressX -> WordPress
    if ( $rpm_provided_module_name_to_app_name{$mod} ) {
        return $rpm_provided_module_name_to_app_name{$mod};
    }

    # Otherwise, just use the third part of the module name as the app name.
    return $app;
}

1;
