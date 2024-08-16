package Whostmgr::DNS::Email;

# cpanel - Whostmgr/DNS/Email.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::DNS::Email - Lookup email data for dns zones.

=head1 SYNOPSIS

    use Whostmgr::DNS::Email;

    my $dns_rp_record = Whostmgr::DNS::Email::getzoneRPemail();

=head1 DESCRIPTION

This module provides contact information for a dns zone.

=cut

use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::Config::LoadCpUserFile  ();
use Cpanel::Hostname                ();

=head2 getzoneRPemail()

Identical to being called with C<root> as argument.

=head2 getzoneRPemail($reseller)

Returns the responsible party record for a dns zone
when given a reseller or root.

=cut

sub getzoneRPemail {
    my $reseller = shift;
    my $contactemail;
    if ( $reseller && $reseller ne 'root' ) {
        ($contactemail) = Cpanel::Config::LoadCpUserFile::load($reseller)->contact_emails_ar()->@*;
    }
    if ( !$contactemail ) {
        my $wwwacctconf_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
        $contactemail = $wwwacctconf_ref->{'CONTACTEMAIL'};
    }
    if ( !$contactemail ) {
        my $hostname = Cpanel::Hostname::gethostname();
        $contactemail = 'root@' . $hostname;
    }
    $contactemail = ( split( m{,}, $contactemail ) )[0];
    $contactemail = ( split( m{;}, $contactemail ) )[0];
    $contactemail =~ tr/ \f\r\n //d;
    my ( $local_part, $domain ) = split( m{@}, $contactemail, 2 );
    $local_part =~ s{\.}{\\\.}g if index( $local_part, '.' ) > -1;
    if ( length $local_part > 63 ) {    #RFC 2142 requires that the local part of the contact email be no more than 63 characters.
        $local_part = "hostmaster";     #If the given email fails this check it will revert to hostmaster@zonedomain
        $domain     = "";               #In the absence of a domain BIND will assume the zone's domain name.
    }
    return $domain ? $local_part . '.' . $domain : $local_part;
}

1;
