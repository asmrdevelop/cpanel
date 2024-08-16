package Whostmgr::API::1::RootIPAccess;

# cpanel - Whostmgr/API/1/RootIPAccess.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::FileUtils::Write ();
use Cpanel::JSON             ();
use Whostmgr::API::1::Utils  ();

use Net::CIDR ();
use Try::Tiny;

use constant NEEDS_ROLE => {
    restrict_whm_root_access  => undef,
    allow_all_whm_root_access => undef,
};

use constant AUTHORIZED_IPS_FILE => '/var/cpanel/authorized_whm_root_ips';

=head1 NAME

Whostmgr::API::1::RootIPAccess - WHM API functions for restricting root access to WHM.

=head2 restrict_whm_root_access()

=head3 Purpose

Takes a list of CIDR addresses which root is authorized to authenticate as on this server.

CAUTION: Once set, this interface will similarly be blocked.

=cut

sub restrict_whm_root_access ( $args, $metadata, @ ) {
    my @cidr_requested = Whostmgr::API::1::Utils::get_length_required_arguments( $args, 'cidr' );

    my @errors;
    my @cidr_to_restrict;

    foreach my $cidr_rule (@cidr_requested) {
        my $ip = Net::CIDR::cidrvalidate($cidr_rule);
        if ( length $ip ) {

            # Will consolodate ranges if possible.
            @cidr_to_restrict = Net::CIDR::cidradd( $ip, @cidr_to_restrict );
        }
        else {
            push @errors, "$cidr_rule is not a valid CIDR address.";

        }
    }

    if (@errors) {
        $metadata->set_not_ok( join( "\n", @errors ) );
        return;
    }

    Cpanel::FileUtils::Write::overwrite( AUTHORIZED_IPS_FILE, Cpanel::JSON::Dump( \@cidr_to_restrict ), 0600 );
    $metadata->set_ok;

    return {
        'cidr' => \@cidr_to_restrict,
    };
}

=head2 allow_all_whm_root_access()

=head3 Purpose

Removes all CIDR controls from accessing WHM

=cut

sub allow_all_whm_root_access ( $args, $metadata, @ ) {
    require Cpanel::Autodie;
    Cpanel::Autodie::unlink_if_exists(AUTHORIZED_IPS_FILE);

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

1;
