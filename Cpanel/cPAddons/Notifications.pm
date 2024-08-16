
# cpanel - Cpanel/cPAddons/Notifications.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Notifications;

use strict;
use warnings;

use Cpanel::cPAddons::Globals    ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::cPAddons::Util       ();

=head1 NAME

Cpanel::cPAddons::Notifications

=head1 DESCRIPTION

Manage the notification setting (~/.cpaddons_notify) for the cPanel side of cPaddons.

=head1 FUNCTIONS

=head2 are_notifications_enabled()

Returns true if notifications are enabled and false otherwise.

B<Important>: This function must not be run as root.

=cut

sub are_notifications_enabled {
    Cpanel::cPAddons::Util::must_not_be_root('Checks for existence of file under user homedir');

    my $user    = $Cpanel::user;
    my $homedir = $Cpanel::homedir;

    return 1 if _exists("$homedir/.cpaddons_notify");
    return 0;
}

=head2 enable_notifications()

Touches the ~/.cpaddons_notify file, which enables cPAddons notifications for the current user.

B<Important>: This function must not be run as root. Running it as root enables the user in
question to perform a symlink attack and gain elevated privileges.

=cut

sub enable_notifications {
    Cpanel::cPAddons::Util::must_not_be_root('Symlink attack: Touches a file under user homedir');

    my $user    = $Cpanel::user;
    my $homedir = $Cpanel::homedir;

    my $path = "$homedir/.cpaddons_notify";

    my $response = {
        action => 'enable',
        path   => $path,
        ok     => 0,
    };

    if ( !_exists($path) ) {
        if ( !Cpanel::FileUtils::TouchFile::touchfile( $path, 0, 1 ) ) {
            return $response;
        }
    }
    $response->{ok} = 1;
    return $response;
}

=head2 disable_notifications()

Removes the ~/.cpaddons_notify file, which disables cPAddons notifications for the current user.

B<Important>: This function must not be run as root. Running it as root enables the user in
question to perform a symlink attack and gain elevated privileges.

=cut

sub disable_notifications {
    Cpanel::cPAddons::Util::must_not_be_root('Checks for existence of file under user homedir');

    my $user    = $Cpanel::user;
    my $homedir = $Cpanel::homedir;

    my $path     = "$homedir/.cpaddons_notify";
    my $response = {
        action => 'disable',
        path   => $path,
        ok     => 0,
    };

    if ( _exists($path) ) {
        if ( !_unlink($path) ) {
            return $response;
        }
    }
    $response->{ok} = 1;
    return $response;

}

=head2 get_setting()

Returns the state of the B<cpaddons_notify_users> Tweak Setting.

=cut

sub get_setting {
    my $cpconf_ref = $Cpanel::cPAddons::Globals::cpconf_ref;
    return $cpconf_ref->{'cpaddons_notify_users'};
}

sub _exists {
    my ($path) = @_;
    return -e $path;
}

sub _unlink {
    my ($path) = @_;
    return unlink $path;
}

1;
