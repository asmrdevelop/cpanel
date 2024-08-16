package Cpanel::Config::IPs::RemoteMail;

# cpanel - Cpanel/Config/IPs/RemoteMail.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Config::IPs::RemoteMail

=head1 SYNOPSIS

    my $contents = Cpanel::Config::IPs::RemoteMail->read();

=head1 DESCRIPTION

This class extends L<Cpanel::Config::IPs::RemoteBase> to provide a read-only
interface to the system’s remote mail IP address datastore.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Config::IPs::RemoteBase';

sub _PATH {
    return '/etc/ips.remotemail';
}

1;
