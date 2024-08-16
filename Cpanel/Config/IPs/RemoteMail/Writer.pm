package Cpanel::Config::IPs::RemoteMail::Writer;

# cpanel - Cpanel/Config/IPs/RemoteMail/Writer.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Config::IPs::RemoteMail::Writer

=head1 SYNOPSIS

    Cpanel::Config::IPs::RemoteMail::Writer->save( \@addresses );

=head1 DESCRIPTION

This class extends L<Cpanel::Config::IPs::RemoteBase::Writer> to provide a
read/write interface to the system’s remote mail IP address datastore.

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::Config::IPs::RemoteBase::Writer',
    'Cpanel::Config::IPs::RemoteMail',
);

1;
