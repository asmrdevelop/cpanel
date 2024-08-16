package Whostmgr::DNS::Kill;

# cpanel - Whostmgr/DNS/Kill.pm                      Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::DNS::Kill - remove DNS zones

=head1 SYNOPSIS

    Whostmgr::DNS::Kill::kill_multiple( 'zone1.tld', 'zone2.tld', );

=cut

#----------------------------------------------------------------------

use Cpanel::DnsUtils::Remove ();
use Whostmgr::ACLS           ();
use Whostmgr::Authz          ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $output = kill_multiple( @ZONES )

Deletes a list of DNS @ZONES from the system by name. Prior to doing any
deletions this validates that the WHM operator has the proper privilege to
remove all of the zones.

The return is the text string output from
C<Cpanel::DnsUtils::Remove::dokilldns()>.

=cut

sub kill_multiple {
    my (@zones) = @_;

    for my $zone (@zones) {
        Whostmgr::Authz::verify_domain_access($zone);

        require Cpanel::Domain::Owner;
        require Cpanel::Config::WebVhosts;

        my $owner = Cpanel::Domain::Owner::get_owner_or_undef($zone);

        next if !$owner || $owner eq 'system';    # These are not in userdata

        my $wvh = Cpanel::Config::WebVhosts->load($owner);

        my $vh_name = $wvh->get_vhost_name_for_domain($zone);

        if ($vh_name) {
            require Cpanel::Exception;
            require Whostmgr::AcctInfo::Owner;
            if ( Whostmgr::ACLS::hasroot() || Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $owner ) ) {
                die Cpanel::Exception::create( 'DomainNameStillConfigured', [ domain => $zone, owner => $owner ] );
            }
            else {
                die Cpanel::Exception::create( 'DomainNameStillConfigured', [ domain => $zone ] );
            }
        }
    }
    my ( $ok, $reason, $out ) = _dokilldns( 'domains' => \@zones );
    die $reason if !$ok;

    return $out;
}

#overridden in tests
*_dokilldns = \*Cpanel::DnsUtils::Remove::dokilldns;

1;
