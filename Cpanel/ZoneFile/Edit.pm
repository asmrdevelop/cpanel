package Cpanel::ZoneFile::Edit;

# cpanel - Cpanel/ZoneFile/Edit.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
# Tools for modifing values in a Cpanel::ZoneFile object
# Mainly used by Cpanel::DnsUtils::Install::Processor
#

use strict;
use warnings;

use parent 'Cpanel::ZoneFile';

our %RECORD_VALUE_MAP = (
    'A'     => ['address'],
    'AAAA'  => ['address'],
    'TXT'   => ['txtdata'],
    'CNAME' => ['cname'],
    'MX'    => [qw(preference exchange)],
    'SRV'   => [qw(priority weight port target)]
);

=encoding utf-8

=head1 NAME

Cpanel::ZoneFile::Edit - Subclass of Cpanel::ZoneFile used for modifying zone file entry "value"

=head1 SYNOPSIS

    use Cpanel::ZoneFile::Edit ();

    my $zone_obj = Cpanel::ZoneFile::Edit->new('domain' => 'koston.org', 'text' => $zone_text);

    my @records = $zone_obj->find_records({'type'=>'A','name'=>"koston.org."});

    my $ip = $zone_obj->get_zone_record_value($records[0]);

    my $newip = '4.4.4.4';

    $zone_obj->set_zone_record_value($records[0],$newip);

    my $new_zone_text = $zone_obj->to_zone_string();

=head1 DESCRIPTION

This module is used by Cpanel::DnsUtils::Install to change
the "values" of A, AAAA, TXT, CNAME, MX, and SRV records.

In this context we define "value" as the text after
the record type.

For example with a dns zone entry of:

 koston.org IN A 5.5.5.5

We define the value as "5.5.5.5"

For example with a dns zone entry of:

 _autodiscover._tcp 14400   IN  SRV 0   0   443 cpanelemaildiscovery.cpanel.net.

We define the value as "0   0   443 cpanelemaildiscovery.cpanel.net."

=head2 set_zone_record_value($dnszone_entry, $value)

This function changes the "value" of a dns zone entry
obtained from a Cpanel::ZoneFile* object.

This function returns 1 upon success and dies on failure.

=cut

sub set_zone_record_value {
    my ( $self, $dnszone_entry, $value ) = @_;
    my $keys_ar = _get_zone_record_keys($dnszone_entry);
    if ( scalar @$keys_ar == 1 ) {
        $dnszone_entry->{ $keys_ar->[0] } = $value;
    }
    else {
        @{$dnszone_entry}{@$keys_ar} = split( m{[ \t]+}, $value );
    }
    $self->{'modified'}           = 1;
    $dnszone_entry->{'unencoded'} = 1;
    return 1;
}

=head2 set_zone_record_value($dnszone_entry)

This function returns the "value" of a dns zone entry
obtained from a Cpanel::ZoneFile* object.

=cut

sub get_zone_record_value {
    my ( $self, $dnszone_entry ) = @_;
    if ( $dnszone_entry->{'type'} eq 'CNAME' ) {
        return $self->_domain( $dnszone_entry->{'cname'} );
    }
    elsif ( $dnszone_entry->{'type'} eq 'SRV' ) {
        return join( " ", $dnszone_entry->{'priority'}, $dnszone_entry->{'weight'}, $dnszone_entry->{'port'}, $self->_domain( $dnszone_entry->{'target'} ) );
    }
    return join( " ", map { $dnszone_entry->{$_} } @{ _get_zone_record_keys($dnszone_entry) } );
}

# Fix the keys used by Cpanel::ZoneFile to construct the record
# value
sub _get_zone_record_keys {
    return $RECORD_VALUE_MAP{ $_[0]->{'type'} } || die "The record type “$_[0]->{'type'}” is not supported by Cpanel::ZoneFile::Edit";
}

1;
