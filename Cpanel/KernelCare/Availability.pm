package Cpanel::KernelCare::Availability;

# cpanel - Cpanel/KernelCare/Availability.pm       Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::License::CompanyID ();
use Cpanel::Config::Sources    ();
use Cpanel::Server::Type       ();
use Cpanel::Exception          ();
use Cpanel::HTTP::Client       ();
use Cpanel::JSON               ();
use Cpanel::Kernel             ();
use Cpanel::LoadFile           ();
use Digest::SHA                ();

sub get_company_advertising_preferences {
    my $id = Cpanel::License::CompanyID::get_company_id();
    chomp $id if defined $id;

    die Cpanel::Exception->create("Cannot determine company ID.") if !$id;
    die Cpanel::Exception->create("Invalid company ID.")          if $id !~ m/^\d+$/;

    my $URL      = sprintf( '%s/kernelcare.cgi', Cpanel::Config::Sources::get_source('MANAGE2_URL') );
    my $response = _ua()->get("$URL?companyid=$id");
    die Cpanel::Exception::create('HTTP') if !$response->{success};

    return Cpanel::JSON::Load( $response->{content} );
}

sub system_license_from_cpanel {

    # FIXME: require instead of use is just a workaround for the circular dependency which really should be eliminated:
    #   Whostmgr::Imunify360 -> Cpanel::KernelCare -> Cpanel::KernelCare::Availability -> Whostmgr::Imunify360
    require Whostmgr::Imunify360;

    my @products_providing_kc = (
        'kernelcare',    # KernelCare does not have a subclass of Whostmgr::Store
        Whostmgr::Imunify360::CPLISC_ID(),
    );
    return ( grep { Cpanel::Server::Type::is_licensed_for_product($_) } @products_providing_kc ) ? 1 : 0;
}

sub kernel_is_supported {
    return if !Cpanel::Kernel::can_modify_kernel();

    my $version = Cpanel::LoadFile::loadfile('/proc/version');
    my $digest  = Digest::SHA::sha1_hex($version);

    my $URL = "https://patches.kernelcare.com/$digest/version";
    eval { _ua()->get($URL) };
    if ( my $err = $@ ) {
        return 0 if ref $err && $err->isa('Cpanel::Exception::HTTP::Server') && $err->status() eq '404';
        die $err;
    }

    return 1;
}

{
    my $_ua;

    sub _ua {
        return $_ua ||= Cpanel::HTTP::Client->new( timeout => 20 )->die_on_http_error();
    }
}

1;

__END__

=encoding utf8

=head1 NAME

Cpanel::KernelCare::Availability - Can KernelCare be installed or advertised?

=head1 DESCRIPTION

This module provides functions for checking license systems regarding
KernelCare.  Specifically, it allows the caller to find a KernelCare license
provided through the cPanel licensing system.  It also checks the license
holder's preferences on how they want KernelCare advertised, if they want it
advertised at all.

=head1 FUNCTIONS

=head2 C<get_company_advertising_preferences()>

Returns the company’s advertising preferences for KernelCare, as specified in
Manage2.

This call checks manage2 for the owning company's preference regarding
KernelCare advertisements in their copy of WHM.  They can set contact
information, as well as completely disable the advertisements.

The preference information returned is determined by manage2.cpanel.net's
output.  At the time of writing, it included the following keys: C<disabled>,
C<url>, & C<email>.

B<Returns:> A hashref with preference information.

B<Dies:> with

=over

=item C<Cpanel::Exception>

When unable to determine the company ID for this server.

=item C<Cpanel::Exception::HTTP>

When the HTTP request is unsuccessful for an unknown reason.

=item C<Cpanel::Exception::HTTP::Server> [from Cpanel::HTTP::Client]

When an error code is returned from the remote server.

=item C<Cpanel::Exception::HTTP::Network> [from Cpanel::HTTP::Client]

When unable to reach the network.

=item C<Cpanel::Exception::JSONParseError> [from Cpanel::JSON]

When unable to parse the JSON returned from the server.

=back

=head2 C<system_license_from_cpanel()>

Returns true if the system indicates a KernelCare or Imunify360 license provided by the cPanel license system.

=head2 C<kernel_is_supported()>

Checks if the currently running kernel is explicitly supported.

This contacts the KernelCare website to see if the currently running kernel is
supported by KernelCare.  If you want a best guess as to whether this system is
supported, without contacting external resources, see
C<Cpanel::KernelCare::system_supports_kernelcare()>.

B<Note:> The full kernel version is used to check for compatibility.  There may
be a short delay between when the software provider adds their new kernel and
when KernelCare adds that kernel version to its supported list.

B<Returns:> 1 if supported; false if unsupported.

B<Dies:> when an error occurs while contacting the KernelCare website.

=cut
