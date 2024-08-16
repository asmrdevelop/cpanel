package Cpanel::DynamicDNS::UtilsBackend;

# cpanel - Cpanel/DynamicDNS/UtilsBackend.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DynamicDNS::UtilsBackend

=head1 SYNOPSIS

n/a

=head1 DESCRIPTION

Logic for use in both privileged and unprivileged dynamic DNS code
that isn’t part of the actual web calls workflow.

This module is only meant to be called by closely-related modules.

=cut

#----------------------------------------------------------------------

use Cpanel::DnsUtils::Name  ();
use Cpanel::UserZones::User ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 @FQDNS = get_ddns_domains( $USERNAME, \@ENTRIES, $ZONENAME )

The backend logic to similar functions in
L<Cpanel::DynamicDNS::UserUtils> and L<Cpanel::DynamicDNS::RootUtils>.

Takes a username, and arrayref of L<Cpanel::WebCalls::Entry::DynamicDNS>
objects, and a $ZONENAME. Returns a list of FQDNs. (In scalar context,
the return is the number of elements in that list.)

=cut

sub get_ddns_domains ( $username, $entries_ar, $zonename ) {
    my @zones = Cpanel::UserZones::User::list_user_dns_zone_names($username);

    my @domains;

    for my $entry (@$entries_ar) {
        my $ddns = $entry->domain();

        my $ddns_zone = Cpanel::DnsUtils::Name::get_longest_short_match(
            $ddns,
            \@zones,
        );

        if ( !$ddns_zone ) {
            warn "$username: No zone found for ddns $ddns!\n";
        }
        elsif ( $ddns_zone eq $zonename ) {
            push @domains, $ddns;
        }
    }

    return @domains;
}

=head2 $errstr = ddns_zone_error( $COUNT, $ZONENAME )

Returns an error that says to delete $COUNT dynamic DNS subdomain(s) from
$ZONENAME before deleting it.

=cut

sub ddns_zone_error ( $ddns_count, $domain ) {
    local ( $@, $! );
    require Cpanel::Locale;
    my $lh = Cpanel::Locale->get_handle();
    return $lh->maketext( '[quant,_1,dynamic DNS domain depends,dynamic DNS domains depend] on “[_2]”. Delete [numerate,_1,that domain,those domains], then try again.', $ddns_count, $domain );
}

1;
