package Cpanel::Sysctl;

# cpanel - Cpanel/Sysctl.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Sysctl

=head1 SYNOPSIS

    my $setting = Cpanel::Sysctl::get('net.ipv4.ip_nonlocal_bind');

=head1 DESCRIPTION

This is a Perl interface to the same kernel variables that
you can otherwise access via L<sysctl(8)>.

=head1 DANGER

If you use this module on CloudLinux it will likely fail
to return results when run as the user.

=cut

#----------------------------------------------------------------------

use Cpanel::LoadFile ();

our $_BASE_PATH = '/proc/sys';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $value = get( $OPTION )

Returns $OPTION’s value.

Note that a handful of settings (e.g., C<sunrpc.transports>) return
multiple values. This interface returns these as F</proc> does,
i.e., as a single string of newline-delimited values.

If $OPTION does not exist, or if any other
error occurs while fetching the value, an exception is thrown.

B<NOTE:> If you need to accommodate the case of a nonexistent setting,
consider creating a separate function rather than depending on
this function’s error response.

=cut

sub get ($opt) {

    $opt =~ tr<./></.>;

    my $val = Cpanel::LoadFile::load("$_BASE_PATH/$opt");
    chomp $val;

    return $val;
}

1;
