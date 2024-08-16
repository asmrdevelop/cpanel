package Cpanel::Template::Plugin::Verify;

# cpanel - Cpanel/Template/Plugin/Verify.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use base 'Template::Plugin';

use Cpanel::License::State ();
use Cpanel::License::Flags ();

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::Verify

=head1 DESCRIPTION

Template toolkit plugin that allows the page developer to gain access to various helper methods and objects
related to product licensing provided via the cPanel Verify APIs.

=head1 SYNOPSIS

  [%
  USE Verify;

  IF Verify.is_trial();
    'The server is currently using a trial license.';
  END;

  IF Verify.is_vps();
    'The server is licensed as a VPS.';
  ELSE;
    'The server is licensed as a dedicated server.';
  END;

  IF Verify.is_developer();
    'The server is licensed for use by developers only.';
  END;

  SET licenses = Verify.query.in_active_paid_license();
  'Licenses on ' _ Verify.query.ip;
  FOREACH license IN licenses;
    '--------------------------------------------';
    'COMPANY: ' _ license.company;
    'PRODUCT: ' _ license.product;
    'PACKAGE: ' _ license.package;
  END;

  SET kind_of_license = Verify.lookup_license_kind(Verify.current_license_status);
  'You are using a: ' _ kind_of_license _ ' license.';

  # If you have handled the previously registed license change event.
  # This is only used by the cp-analytics plugin when sending
  # cp-license-change events.
  Verify.clear_license_changed_event();

=head1 CONSTRUCTOR

=head2 new(CONTEXT)

Constructor for the plugin.

=cut

sub new {
    my ($class) = @_;

    return bless {}, $class;
}

=head2 PLUGIN->has_license_changed()

Check if there has been a license change recorded since the last time a page was rendered.

=head3 RETURNS

Returns 1 if the server license has changed since the last GA reporting, 0 otherwise.

=cut

sub has_license_changed ($plugin) {
    return Cpanel::License::State::has_changed();
}

=head2 PLUGIN->clear_license_changed_event()

Clear the license change flag.

=cut

sub clear_license_changed_event ($plugin) {
    return Cpanel::License::State::clear_changed();
}

=head2 PLUGIN->is_trial()

Check if the server is running with a trial license.

=head3 RETURNS

Returns 1 if the server is running on a trial license, 0 otherwise.

=cut

sub is_trial ($plugin) {
    return Cpanel::License::Flags::has_flag('trial');
}

=head2 PLUGIN->is_vps()

Check if the server is running with a vps license.

=head3 RETURNS

Returns 1 if the server is running on a vps license, 0 otherwise.

=cut

sub is_vps ($plugin) {
    return Cpanel::License::Flags::has_flag('vps');
}

=head2 PLUGIN->is_developer()

Check if the server is running with a developer license.

=head3 RETURNS

Returns 1 if the server is running on a developer license, 0 otherwise.

=cut

sub is_developer ($plugin) {
    return Cpanel::License::Flags::has_flag('dev');
}

=head2 PLUGIN->current_license_status()

Check the license status for the server.

=head3 RETURNS

See C<Cpanel::License::State::current_state()> for information
on the return value.

=cut

sub current_license_status ($plugin) {
    return Cpanel::License::State::current_state();
}

=head2 PLUGIN->has_expired_license()

Check if there is only an expired product license.

=head3 RETURNS

1 if there is an expired license, but no active product license; 0 otherwise.

=cut

sub has_expired_license ($plugin) {
    return Cpanel::License::State::is_expired();
}

=head2 PLUGIN->lookup_license_kind($kind)

Get the map of the various names of kinds of license conditions the get_status can detect.

=head3 RETURNS

Reverse lookup hash with value to name mappings.

=cut

sub lookup_license_kind ( $plugin, $kind = Cpanel::License::State::current_state() ) {
    return Cpanel::License::State::state_to_name($kind);
}

1;
