package Cpanel::TailWatch::APNSPush::Config;

# cpanel - Cpanel/TailWatch/APNSPush/Config.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Locale ();

our $VERSION = 0.1;

my $locale;

sub REQUIRED_ROLES {
    return [qw< MailReceive >];
}

=encoding utf-8

=head1 NAME

Cpanel::TailWatch::APNSPush::Config - Configration for the Cpanel::TailWatch::APNSPush module

=head1 SYNOPSIS

    use Cpanel::TailWatch::APNSPush::Config;

    my $managed = Cpanel::TailWatch::APNSPush::is_managed_by_tailwatchd();

    my $text = Cpanel::TailWatch::APNSPush::description();

=cut

=head2 is_managed_by_tailwatchd

Sets the managed flag in tailwatchd (this currently does not appear to do anything)

=head3 Input

None

=head3 Output

Always returns 1

=cut

sub is_managed_by_tailwatchd {
    return 1;
}

=head2 description

Returns the description of the module suitable for being displayed in the UI.

=head3 Input

None

=head3 Output

Returns a localized string.

=cut

sub description {
    return ( $locale ||= Cpanel::Locale->get_handle() )->maketext("Responsible for notifying iOS devices when new mail arrives.");
}

1;
