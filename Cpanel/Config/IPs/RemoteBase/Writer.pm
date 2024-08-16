package Cpanel::Config::IPs::RemoteBase::Writer;

# cpanel - Cpanel/Config/IPs/RemoteBase/Writer.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Config::IPs::RemoteBase::Writer

=head1 SYNOPSIS

XXXX

=head1 DESCRIPTION

This class extends L<Cpanel::Config::IPs::RemoteBase> with logic to
write the datastore.

=head1 TODO

This doesn’t provide race safety because there’s no check that the
contents we’re overwriting are what we I<meant> to overwrite.
One potential fix would be to have C<save()> accept an additional
array reference of what the caller intends to overwrite; if that
array doesn’t match the datastore’s pre-overwrite contents, then
we can fail the request.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Config::IPs::RemoteBase';

use Cpanel::Exception        ();
use Cpanel::FileUtils::Write ();
use Cpanel::Sort::Utils      ();
use Cpanel::Ips::V6          ();
use Cpanel::Validate::IP::v4 ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->write( \@NEW )

Saves @NEW as the datastore contents.

Returns nothing.

=cut

sub write ( $class, $input_ar ) {
    my ( @ipv4, @ipv6 );

    my @invalid;

    for my $specimen (@$input_ar) {
        if ( Cpanel::Validate::IP::v4::is_valid_ipv4($specimen) ) {
            push @ipv4, $specimen;
        }
        elsif ( Cpanel::Ips::V6::validate_ipv6($specimen) ) {
            push @ipv6, $specimen;
        }
        else {
            push @invalid, $specimen;
        }
    }

    if (@invalid) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "Invalid: @invalid" );
    }

    # Do we have IPv6 sorting logic?
    if (@ipv4) {
        require Cpanel::Sort::Utils;
        @ipv4 = Cpanel::Sort::Utils::sort_ipv4_list( \@ipv4 );
    }

    if (@ipv6) {
        require Cpanel::IPv6::Sort;
        Cpanel::IPv6::Sort::in_place( \@ipv6 );
    }

    Cpanel::FileUtils::Write::overwrite(
        $class->_PATH(),

        # Save IPv6 first since in theory it’ll displace IPv4 someday.
        join( "\n", @ipv6, @ipv4, q<> ),

        0644,
    );

    return;
}

1;
