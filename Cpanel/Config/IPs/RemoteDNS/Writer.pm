package Cpanel::Config::IPs::RemoteDNS::Writer;

# cpanel - Cpanel/Config/IPs/RemoteDNS/Writer.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Config::IPs::RemoteMail::Writer

=head1 SYNOPSIS

    Cpanel::Config::IPs::RemoteDNS::Writer->save( \@addresses );

=head1 DESCRIPTION

This class extends L<Cpanel::Config::IPs::RemoteBase::Writer> to provide a
read/write interface to the system’s remote DNS IP address datastore.

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::Config::IPs::RemoteBase::Writer',
    'Cpanel::Config::IPs::RemoteDNS',
);

1;
