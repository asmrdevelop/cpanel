package Cpanel::Systemd;

# cpanel - Cpanel/Systemd.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Systemd

=head1 SYNOPSIS

    my $names_ar = get_service_names_ar();

=head1 DESCRIPTION

This module corrals logic to speak with systemd.

=cut

#----------------------------------------------------------------------

use Carp ();

use Cpanel::FindBin         ();
use Cpanel::SafeRun::Object ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $names_ar = get_service_names_ar()

Retrieves a list of names of systemd’s loaded services (e.g., C<crond>).

Note that this doesn’t distinguish between active/inactive or
enabled/disabled services.

=cut

sub get_service_names_ar {

    # TODO: We should ideally have a way to talk to D-Bus from Perl,
    # but this should be stable enough. It seems a bit more robust than
    # parsing `systemctl --type=service`, anyway.
    #
    # cf. https://www.freedesktop.org/wiki/Software/systemd/dbus/
    #
    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => '/usr/bin/dbus-send',
        args    => [
            '--system',
            '--print-reply=literal',
            '--type=method_call',
            '--dest=org.freedesktop.systemd1',
            '/org/freedesktop/systemd1',
            'org.freedesktop.systemd1.Manager.ListUnits',
        ],
    );

    my @services = $run->stdout() =~ m<^\s+(\S+)\.service>mg;
    return \@services;
}

#----------------------------------------------------------------------

=head2 $run = systemctl( @ARGS )

Runs L<systemctl(1)> with the given @ARGS. Returns a
L<Cpanel::SafeRun::Object> instance that represents the result.

An appropriate L<Cpanel::Exception> instance is thrown if
systemctl doesn’t finish cleanly.

=cut

my $systemctl_bin;

sub systemctl (@args) {
    state $systemctl_bin = Cpanel::FindBin::findbin('systemctl');

    return Cpanel::SafeRun::Object->new_or_die(
        program => $systemctl_bin,
        args    => \@args,
    );
}

#----------------------------------------------------------------------

=head2 $filename = path_to_mount_filename( $ABSOLUTE_PATH )

systemd requires that C<.mount> units be named according to their mount
point. This converts a mount point’s path to the filename that systemd
expects it to be.

=cut

sub path_to_mount_filename ($path) {
    Carp::croak("Path ($path) must be absolute!") if 0 != index( $path, '/' );

    return escape( substr( $path, 1 ) ) . '.mount';
}

=head2 $escaped = escape( $STRING )

Like C<path_to_mount_filename()> but just encodes $STRING generically,
without making it a filename that systemd expects.

(NB: $PATH can be relative.)

=cut

sub escape ($path) {

    # Ported from https://docs.rs/libsystemd/0.5.0/src/libsystemd/unit.rs.html
    $path =~ s<([^/.:_0-9a-zA-Z]|\A\.)><sprintf '\\x%02x', ord $1>ge;
    $path =~ tr</><->;

    return $path;
}

1;
