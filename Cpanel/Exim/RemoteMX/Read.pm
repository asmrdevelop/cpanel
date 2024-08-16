package Cpanel::Exim::RemoteMX::Read;

# cpanel - Cpanel/Exim/RemoteMX/Read.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exim::RemoteMX::Read

=head1 DESCRIPTION

Reader for the contents of the remote mx ips

=cut

#----------------------------------------------------------------------

use CDB_File                          ();
use List::Util                        ();
use Cpanel::Exception                 ();
use Cpanel::Exim::RemoteMX::Constants ();

# mocked in tests
*_PATH = *Cpanel::Exim::RemoteMX::Constants::PATH;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @ips = all_ips()

Reads the remote MX IPs file and returns all the IP addresses for all
domains in a single (deduplicated, unordered) list.

=cut

sub all_ips {

    my $sep = Cpanel::Exim::RemoteMX::Constants::IP_SEPARATOR;

    # Ips are stored for exim are need to be unscaped by converting :: to :
    return List::Util::uniqstr( map { s<$sep$sep><$sep>gr } map { split( /\s+$sep\s+/o, $_ ); } values %{ _read() } );
}

sub _read {
    my %cdb;

    my $catref = tie %cdb, 'CDB_File', _PATH() or do {
        return {} if $!{'ENOENT'};

        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => _PATH(), error => $! ] );
    };

    my $data = $catref->fetch_all();
    undef $catref;
    untie %cdb;
    return $data;
}

1;
