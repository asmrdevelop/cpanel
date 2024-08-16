package Whostmgr::DNS;

# cpanel - Whostmgr/DNS.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=cut

use Cpanel::DnsUtils::RR                 ();
use Cpanel::NameserverCfg                ();
use Cpanel::Validate::Domain::Tiny       ();
use Cpanel::DnsUtils::Stream             ();
use Cpanel::DnsUtils::AskDnsAdmin        ();
use Cpanel::Debug                        ();
use Cpanel::ZoneFile                     ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::AcctUtils::Owner             ();
use Whostmgr::ACLS                       ();
use Cpanel::Validate::IP                 ();
use Cpanel::Validate::IP::v4             ();
use Cpanel::Validate::IP::Expand         ();
use Whostmgr::DNS::Zone                  ();
use Whostmgr::DNS::Email                 ();

=head1 FUNCTIONS

=cut

{
    no warnings 'once';

    *fetchdnszone             = *Whostmgr::DNS::Zone::fetchdnszone;
    *_bump_serial_number      = *Whostmgr::DNS::Zone::_bump_serial_number;
    *get_zone_records_by_type = *Whostmgr::DNS::Zone::get_zone_records_by_type;
    *upsrnumstream            = *Cpanel::DnsUtils::Stream::upsrnumstream;
    *getnewsrnum              = *Cpanel::DnsUtils::Stream::getnewsrnum;
    *getzoneRPemail           = *Whostmgr::DNS::Email::getzoneRPemail;
}

sub upsrnum {
    my ($zonef) = @_;

    my $domain = $zonef;
    $domain =~ s/\.db\z//g;
    my @ZFILE    = split( "\n", Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "GETZONE", 0, $domain ) );
    my $zonedata = join( "\n", @ZFILE );
    $zonedata = upsrnumstream($zonedata);
    return Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "SAVEZONE", 0, $domain, $zonedata );
}

sub updatesoastream {
    my $zone_data = shift;
    my $creator   = shift;

    my $rpemail     = Whostmgr::DNS::Email::getzoneRPemail($creator);
    my @nameservers = Cpanel::NameserverCfg::fetch($creator);

    my $soaserver_rec = $nameservers[0] . '.';
    my $rp_email_rec  = $rpemail . '.';

    if ( $zone_data =~ m/(\s+SOA\s+)\S+(\s+)\S+(\s+\([\n\s]+\d+[\s\n\;]+)/m ) {
        $zone_data =~ s/(\s+SOA\s+)\S+(\s+)\S+(\s+\([\n\s]+\d+[\s\n\;]+)/$1$soaserver_rec$2$rp_email_rec$3/m;
    }
    return $zone_data;
}

sub getnameservers {
    goto &Cpanel::NameserverCfg::fetch;
}

#
# update_ttls_in_zones:
#
# Takes Positional arguments:
#  * arrayref containing the list of domains to modify
#  * the newttl to set in the zones
#  * boolean value indicating if we should not perform a synczones action
# Returns true if no errors were encountered in non-list context.
# Returns true, and an arrayref to the list of zones that were updated successfully in list context.
# Used by /usr/local/cpanel/bin/set_zone_ttl utility
# Used by /scripts/setzonettl in WHM
#
sub update_ttls_in_zones {
    my $domains_to_modify_ar = shift;
    my $newttl               = shift;
    my $local_change_only    = shift || 0;

    return unless ref $domains_to_modify_ar eq 'ARRAY' and scalar @{$domains_to_modify_ar};
    if ( $newttl !~ m/\A[0-9]+\z/ ) {
        print "\n[!] Invalid TTL specified. TTL must be a numeric value.\n";
        return;
    }

    Whostmgr::ACLS::init_acls();
    my $running_as_root = Whostmgr::ACLS::hasroot();
    print "\n[*] Updating " . scalar @{$domains_to_modify_ar} . " Domain(s)...\n";
    my $count = 0;
    my @zones_updated;
    foreach my $domain ( @{$domains_to_modify_ar} ) {
        print "\n[*] (" . ++$count . '/' . scalar @{$domains_to_modify_ar} . ") Processing '$domain'...\n";

        if ( !( $running_as_root || _check_domain_ownership($domain) ) ) {
            print "[!] Sorry, you do not have permission to modify '$domain'\n";
        }
        else {
            my $zonefile_content = fetchdnszone($domain);
            if ( ref $zonefile_content eq 'ARRAY' && scalar @{$zonefile_content} ) {
                my $zonefile_obj = Cpanel::ZoneFile->new( text => $zonefile_content, domain => $domain );
                $zonefile_obj->forcettl($newttl);
                my $new_zonedata = join( "\n", $zonefile_obj->build_zone() ) . "\n";
                $new_zonedata = Cpanel::DnsUtils::Stream::upsrnumstream($new_zonedata);

                # if $local_change_only is true, then the changes will NOT propagate across the cluster after the zones have been updated locally.
                Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'SAVEZONE', $local_change_only, $domain, $new_zonedata );
                Cpanel::Debug::log_info("Set TTL for '$domain' to '$newttl'");
                print "[+] Set TTL for '$domain' to '$newttl'\n";
                push @zones_updated, $domain;
            }
            else {
                print "[!] '$domain' not found. Skipping...\n";
            }
        }
    }
    print "\n";

    if ( scalar @zones_updated ) {
        print "[*] Reloading zones...\n";
        Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADZONES', 0, join( ',', @zones_updated ) );
    }
    print "[+] Done\n";
    return wantarray ? ( 1, \@zones_updated ) : 1;
}

sub _check_domain_ownership {
    my $domain = shift;

    my $domain_user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);
    my $user_owner  = Cpanel::AcctUtils::Owner::getowner($domain_user) || 'root';

    if ( $domain_user eq $ENV{'REMOTE_USER'} || $user_owner eq $ENV{'REMOTE_USER'} ) {
        return 1;
    }

    return;
}

sub _send_updated_zones {
    my $zone_ref = shift;

    # If there is only one zone we use _send_updated_zone
    # To avoid the overhead of SYNCZONES
    if ( scalar keys %$zone_ref == 1 ) {
        my $zonefile = ( keys %$zone_ref )[0];
        return _send_updated_zone( $zonefile, $zone_ref->{$zonefile} );
    }

    my ( $encoded_zone_data, @RELOADLIST ) = ('');
    foreach my $zone ( keys %$zone_ref ) {
        my $arrayref_zone_data = ref $zone_ref->{$zone} eq 'Cpanel::ZoneFile' ? $zone_ref->{$zone}->serialize() : ref $zone_ref->{$zone} eq 'ARRAY' ? $zone_ref->{$zone} : '';
        if ($arrayref_zone_data) {
            $encoded_zone_data .= 'cpdnszone-' . cPScript::Encoder::URI::uri_encode_str($zone) . '=' . cPScript::Encoder::URI::uri_encode_str( join( "\n", @$arrayref_zone_data ) ) . '&';
            push @RELOADLIST, $zone;
        }
        else {

            # invalid arguments
            die "Invalid data passed to Whostmgr::DNS::_send_updated_zones (zone for $zone is not an arrayref or Cpanel::ZoneFile object)";
        }

    }

    Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "SYNCZONES", 0, '', '', '', $encoded_zone_data );
    Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADZONES', 0, join( ',', @RELOADLIST ) );
    return ( 1, 'Zones Saved' );
}

sub _send_updated_zone {
    my $domain      = shift;
    my $zonedataref = shift;
    my $newserial   = shift;
    if ( !$domain ) {
        return ( 0, "_send_updated_zones requires a domain/zonefile to save." );
    }

    my $arrayref_zonedata = ref $zonedataref eq 'Cpanel::ZoneFile' ? $zonedataref->serialize() : ref $zonedataref eq 'ARRAY' ? $zonedataref : '';

    if ( !$arrayref_zonedata ) {
        return ( 0, "Invalid or missing zonedata provided for $domain" );
    }

    my $zonedata = join( "\n", @$arrayref_zonedata ) . "\n";

    my $results = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'SAVEZONE', 0, $domain, $zonedata );
    $results .= Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADBIND', 0, $domain );

    # There's no good way to check these for errors.  Success is just assumed.
    return 1, $results, $newserial;
}

sub get_zone_record {
    my ( $record_ref, %args ) = @_;
    my $domain = $args{'domain'};
    my $line   = abs int $args{'Line'};

    if ( !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {
        return 0, 'Invalid domain specified.';
    }
    elsif ( !$line ) {
        return 0, 'Must specify a record line.';
    }

    my $lines_ref = fetchdnszone($domain);

    if ( !$lines_ref ) {
        return 0, 'No data read from zone file.';
    }

    my $zonefile = Cpanel::ZoneFile->new( 'domain' => $domain, 'text' => $lines_ref );

    if ( $zonefile->{'status'} == 0 ) {
        return 0, $zonefile->{'error'};
    }

    my $record = $zonefile->get_record($line);

    if ( !$record ) {
        return 0, 'No record available on selected line.';
    }

    $$record_ref = $record;
    return 1, 'Record obtained.';
}

sub save_mxs {
    my ( $domain, $records, $serialnum ) = @_;
    my $mxs = [];
    my @mx_lines;
    my ( $result, $msg ) = Whostmgr::DNS::Zone::get_zone_records_by_type( $mxs, $domain, 'MX' );
    if ( !$result ) {
        return $result, 'Failed to fetch zone records: ' . $msg;
    }
    foreach my $mx (@$mxs) {
        push @mx_lines, $mx->{'Line'};
    }

    my ( $remove_result, $remove_why, $zonefile_obj ) = remove_zone_records( \@mx_lines, $serialnum, $domain );
    return ( $remove_result, $remove_why ) if !$remove_result;

    my ( $add_result, $add_why ) = add_zone_records( $records, $domain, $zonefile_obj );
    return ( $add_result, $add_why ) if !$add_result;

    my ( $valid_result, $valid_why, $newlines_ref, $newserial ) = _zone_is_valid( $zonefile_obj, $domain );
    return ( $valid_result, $valid_why ) if !$valid_result;

    return _send_updated_zone( $domain, $newlines_ref, $newserial );
}

sub _serial_number_matches {
    my ( $zonefile, $old_serial ) = @_;
    return 1 if !defined $old_serial;
    return $zonefile->get_serial_number() eq $old_serial;
}

sub edit_zone_record {
    my ( $arg_ref, $domain, $zonefile_obj ) = @_;
    if ( !$arg_ref || ref $arg_ref ne 'HASH' ) {
        return 0, 'Invalid arguments specified';
    }
    if ( !$domain ) { $domain = $arg_ref->{'domain'}; }
    my $line = abs int $arg_ref->{'Line'};

    # CNAME flattening
    # If the record we are modifying is for the root domain,
    # and we setting it to a CNAME record, then check for flattening options
    if ( $arg_ref->{'flatten'} && $arg_ref->{'name'} =~ m/\A$domain\.?\z/ && $arg_ref->{'type'} eq 'CNAME' ) {
        $arg_ref->{'type'} = 'A';
        my $flatten_domain = delete $arg_ref->{'cname'};
        if ( $arg_ref->{'flatten_to'} ) {
            if ( Cpanel::Validate::IP::is_valid_ip( $arg_ref->{'flatten_to'} ) ) {
                $arg_ref->{'address'} = $arg_ref->{'flatten_to'};
            }
            else {
                return 0, 'Invalid flatten_to specified. Must be a valid IP address.';
            }
        }
        else {
            if ( my $address = _resolve_record($flatten_domain) ) {
                $arg_ref->{'address'} = $address;
            }
            else {
                return 0, "Unable to resolve specified flatten address: “$flatten_domain”.";
            }
        }
    }

    if ( !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {
        return 0, 'Invalid domain specified.';
    }
    elsif ( !$line ) {
        return 0, 'Must specify a line to edit.';
    }

    if ( !ref $zonefile_obj ) {
        my $lines_ref = fetchdnszone($domain);

        if ( !$lines_ref ) {
            return 0, 'No data read from zone file.';
        }
        $zonefile_obj = Cpanel::ZoneFile->new( 'domain' => $domain, 'text' => $lines_ref );
    }
    if ( $zonefile_obj->{'status'} == 0 ) {
        return 0, $zonefile_obj->{'error'};
    }
    if ( !_serial_number_matches( $zonefile_obj, $arg_ref->{'serialnum'} ) ) {
        return 0, 'Zone file changed since last read.';
    }

    delete $arg_ref->{'serialnum'};

    my $record = $zonefile_obj->get_record($line);
    while ( my ( $k, $v ) = each %$arg_ref ) {
        $record->{$k} = $v;
    }

    $record->{'type'} = 'CAA' if ( $record->{'type'} eq 'TYPE257' );

    my ( $sanitize_status, $sanitize_msg ) = sanitize_record($record);
    return ( $sanitize_status, $sanitize_msg ) if !$sanitize_status;

    my ( $status, $statusmsg, $serialized_record ) = $zonefile_obj->serialize_single_record($record);
    if ( !$status ) {
        return 0, $statusmsg;
    }
    if ( length($serialized_record) > 65535 ) {    #record RFC
        return 0, "Records may not exceed 65535 bytes";
    }

    my ( $validate_status, $validate_statusmsg ) = validate_dnszone_with_changes( $domain, $record, $zonefile_obj->{'dnszone'} );
    if ( !$validate_status ) {
        return ( $validate_status, $validate_statusmsg );
    }

    $zonefile_obj->replace_records( [$record] );
    my ( $result, $msg, $newserial ) = _bump_serial_number($zonefile_obj);
    return 0, $msg if !$result;

    my $newlines_ref = $zonefile_obj->build_zone_for_display();
    my $newzonefile  = Cpanel::ZoneFile->new( 'domain' => $domain, 'text' => $newlines_ref );
    if ( $newzonefile->{'status'} == 0 ) {
        return 0, $newzonefile->{'error'};
    }

    return _send_updated_zone( $domain, scalar $newzonefile->build_zone(), $newserial );
}

sub _zone_is_valid {
    my ( $zonefile_obj, $domain ) = @_;

    my ( $result, $msg, $newserial ) = _bump_serial_number($zonefile_obj);
    return ( 0, $msg ) if !$result;

    my $newlines_ref = $zonefile_obj->build_zone_for_display();
    my $newzonefile  = Cpanel::ZoneFile->new( 'domain' => $domain, 'text' => $newlines_ref );
    if ( $newzonefile->{'status'} == 0 ) {
        return 0, $newzonefile->{'error'};
    }
    return 1, 'OK', scalar $newzonefile->build_zone(), $newserial;
}

# Does not test or install new zone
sub add_zone_records {
    my ( $record_list_ref, $domain, $zonefile_obj ) = @_;

    if ( !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {
        return 0, 'Invalid domain specified.';
    }

    if ( !ref $zonefile_obj ) {
        my $lines_ref = fetchdnszone($domain);

        if ( !$lines_ref ) {
            return 0, 'No data read from zone file.';
        }

        $zonefile_obj = Cpanel::ZoneFile->new( 'domain' => $domain, 'text' => $lines_ref );

        if ( $zonefile_obj->{'status'} == 0 ) {
            return 0, $zonefile_obj->{'error'};
        }
    }

    foreach my $record (@$record_list_ref) {
        $record->{'type'} = 'CAA' if ( $record->{'type'} eq 'TYPE257' );
        my ( $sanitize_status, $sanitize_msg ) = sanitize_record($record);
        return ( $sanitize_status, $sanitize_msg ) if !$sanitize_status;

        my ( $status, $statusmsg, $serialized_record ) = $zonefile_obj->serialize_single_record($record);
        if ( !$status ) {
            return 0, $statusmsg;
        }

        # Per record RFC
        if ( length($serialized_record) > 65535 ) {
            return 0, "Records may not exceed 65535 bytes";
        }

        my ( $validate_status, $validate_statusmsg ) = validate_dnszone_with_changes( $domain, $record, $zonefile_obj->{'dnszone'} );
        return ( $validate_status, $validate_statusmsg ) if ( !$validate_status );

        $zonefile_obj->add_record($record);
    }

    return 1, 'OK', $zonefile_obj;
}

sub add_zone_record {
    my ( $arg_ref, $domain ) = @_;
    if ( !$arg_ref || ref $arg_ref ne 'HASH' ) {
        return 0, 'Invalid arguments specified';
    }
    if ( !$domain ) {
        $domain = $arg_ref->{'domain'};
    }

    my ( $add_result, $add_why, $zonefile_obj ) = add_zone_records( [$arg_ref], $domain );
    return ( $add_result, $add_why ) if !$add_result;

    my ( $valid_result, $valid_why, $newlines_ref, $newserial ) = _zone_is_valid( $zonefile_obj, $domain );
    return ( $valid_result, $valid_why ) if !$valid_result;

    return _send_updated_zone( $domain, $newlines_ref, $newserial );
}

# Does not test or install new zone
sub remove_zone_records {
    my ( $line_number_list_ref, $serialnum, $domain, $zonefile_obj ) = @_;

    if ( !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {
        return 0, 'Invalid domain specified.';
    }

    if ( !ref $zonefile_obj ) {
        my $lines_ref = fetchdnszone($domain);

        if ( !$lines_ref ) {
            return 0, 'No data read from zone file.';
        }
        $zonefile_obj = Cpanel::ZoneFile->new( 'domain' => $domain, 'text' => $lines_ref );
    }

    if ( $zonefile_obj->{'status'} == 0 ) {
        return 0, $zonefile_obj->{'error'};
    }
    if ( !_serial_number_matches( $zonefile_obj, $serialnum ) ) {
        return 0, 'Zone file changed since last read.';
    }

    my @records_to_remove;
    foreach my $line (@$line_number_list_ref) {
        my $record = $zonefile_obj->get_record($line);
        if ( !defined $record ) {
            return 0, 'Unable to find a record on specified line: ' . int $line;
        }
        if ( $record->{'type'} eq 'SOA' ) {
            return 0, 'You cannot remove the SOA record.';
        }
        push @records_to_remove, $record;
    }
    $zonefile_obj->remove_records( \@records_to_remove );

    return 1, 'OK', $zonefile_obj;
}

=head2 remove_zone_record( $ARGS_HR, $OPTIONAL_ZONEFILE )

$ARGS_HR is:

=over

=item C<domain> - The DNS zone to edit.

=item C<Line> - The line number of the record to remove.

=item C<serialnum> - The DNS zone’s serial number (i.e. from the last read).

=back

$OPTIONAL_ZONEFILE, if given, is a L<Cpanel::ZoneFile> instance.

Returns a ($status, $reason) pair.

=cut

sub remove_zone_record {
    my ( $arg_ref, $zonefile_obj ) = @_;
    if ( !$arg_ref || ref $arg_ref ne 'HASH' ) {
        return 0, 'Invalid arguments specified';
    }

    my $domain = $arg_ref->{'domain'};
    my $line   = abs int $arg_ref->{'Line'};

    my ( $remove_result, $remove_why );
    ( $remove_result, $remove_why, $zonefile_obj ) = remove_zone_records( [$line], $arg_ref->{'serialnum'}, $domain, $zonefile_obj );
    return ( $remove_result, $remove_why ) if !$remove_result;

    my ( $valid_result, $valid_why, $newlines_ref, $newserial ) = _zone_is_valid( $zonefile_obj, $domain );
    return ( $valid_result, $valid_why ) if !$valid_result;

    return _send_updated_zone( $domain, $newlines_ref, $newserial );
}

sub validate_dnszone_with_changes {
    my ( $domain, $newrecord, $dnszone_ref ) = @_;
    my $rootdomain = $domain . '.';
    if ( exists $newrecord->{'Line'} && exists $newrecord->{'line'} ) {
        $newrecord->{'Line'} = $newrecord->{'line'};
    }
    my $newname = ( $newrecord->{'name'} =~ /\.\z/ ? $newrecord->{'name'} : $newrecord->{'name'} . '.' . $domain . '.' );
    my $newtype = $newrecord->{'type'};
    if ( $newname !~ /\.$domain\.\z/ && $newname !~ /^$domain\.\z/ ) {
        return ( 0, $newname . ' is outside the current dns zone: ' . $domain . '.' );
    }
    my $newline = $newrecord->{'Line'} || 0;
    for ( 0 .. $#{$dnszone_ref} ) {
        if ( ( $dnszone_ref->[$_]->{'name'} || '' ) eq $newname && ( $dnszone_ref->[$_]->{'Line'} || 0 ) != $newline ) {
            if ( $dnszone_ref->[$_]->{'type'} eq 'CNAME' && $newtype eq 'CNAME' ) {
                return ( 0, $newname . " already has a CNAME record.\nYou have multiple CNAME records." );
            }
            elsif ( $newtype eq 'CNAME' ) {
                return ( 0, $newname . ' already has a ' . $dnszone_ref->[$_]->{'type'} . " record.\nYou may not mix CNAME records with other records for the same name." );
            }
            elsif ( $dnszone_ref->[$_]->{'type'} eq 'CNAME' ) {
                return ( 0, $newname . " already has a CNAME record.\nYou may not mix CNAME records with other records (" . $newtype . ').' );
            }
        }
    }
    return 1, 'OK';
}

# Per RFC 1035, section 2.3.1 (but allowing numerics as the first character)
sub _is_valid_hostname_label {
    my $label = shift;

    return length($label) < 64 && $label =~ m/\A[a-z\d]([-a-z\d]*[a-z\d])?\z/i;
}

# Loosen restrictions on non-hostname DNS labels. See RFC 2181, section 11.
# Allows use of underscores throughout CNAME records (used for DKIM verification).
sub _is_valid_dns_label {
    my $label = shift;

    # Case 41330: allow single wildcard in DNS record.
    if ( $label eq '*' ) { return 1; }

    return length($label) < 64 && $label =~ m/\A[a-z\d_]([-a-z\d_]*[a-z\d_])?\z/i;
}

# Previously validated using Cpanel::Validate::Domain::Tiny::validdomainname.
# DNS labels are more permissive, however, so used looser checking.
sub _is_valid_hostname {
    my $domain = shift;
    return if !$domain;
    $domain =~ s/\.\z//;

    my @parts = split( /\./, $domain );
    return if scalar(@parts) < 2;

    foreach my $part (@parts) {
        return if !_is_valid_hostname_label($part);
    }
    return 1;
}

# Loosen restrictions on non-hostname DNS labels. See RFC 2181, section 11.
sub _is_valid_dns_domain {
    my $domain = shift;
    return if !$domain;
    $domain =~ s/\.\z//;

    my @parts = split( /\./, $domain );
    return if scalar(@parts) < 2;

    foreach my $part (@parts) {
        return if !_is_valid_dns_label($part);
    }
    return 1;
}

sub _keep_only_relevant_keys {
    my ( $record, @keys ) = @_;
    push @keys, 'name', 'Line', 'class', 'ttl', 'type';
    my %keep_key;

    foreach my $key (@keys) {
        $keep_key{$key} = 1;
    }

    foreach my $key ( keys %$record ) {
        if ( !exists $keep_key{$key} ) {
            delete $record->{$key};
        }
    }
}

# Validating records based on RFC 1035
my %record_sanitizer_for_type = (
    'A' => sub {
        my $record = shift;

        # allow the non-routable meta-address (0.0.0.0) to be set
        my $is_meta_address = length $record->{'address'} && $record->{'address'} eq '0.0.0.0';
        if ( !$is_meta_address ) {
            $record->{'address'} = Cpanel::Validate::IP::Expand::normalize_ipv4( $record->{'address'} );
            if ( !$record->{'address'} ) {
                return 0, 'Supplied address for A record is invalid';
            }
        }

        _keep_only_relevant_keys( $record, 'address' );
        return 1;
    },
    'AAAA' => sub {
        my $record = shift;

        if ( !Cpanel::Validate::IP::is_valid_ipv6( $record->{'address'} ) ) {
            return 0, 'Supplied address for AAAA record is invalid';
        }

        _keep_only_relevant_keys( $record, 'address' );
        return 1;
    },
    'CNAME' => sub {
        my $record = shift;

        if ( !_is_valid_dns_domain( $record->{'cname'} ) ) {
            return 0, 'Supplied CNAME is invalid.';
        }
        if ( Cpanel::Validate::IP::is_valid_ipv6( $record->{'cname'} ) ) {
            return 0, 'CNAMEs can not point to an IPv6 address';
        }
        if ( Cpanel::Validate::IP::v4::is_valid_ipv4( $record->{'cname'} ) ) {
            return 0, 'CNAMEs can not point to an IPv4 address';
        }

        # Make sure we have at least two labels.
        if ( $record->{'cname'} !~ /.+\..+\.?\z/ ) {
            return 0, 'CNAMEs must point a FQDN (Fully Qualified Domain Name).';
        }

        _keep_only_relevant_keys( $record, 'cname' );
        return 1;
    },
    'NS' => sub {
        my $record = shift;
        if ( !_is_valid_hostname( $record->{'nsdname'} ) ) {
            return 0, 'Supplied NS is invalid.';
        }

        _keep_only_relevant_keys( $record, 'nsdname' );
        return 1;
    },
    'MX' => sub {
        my $record = shift;
        $record->{'exchange'} =~ s/\.\z//;

        if ( Cpanel::Validate::IP::v4::is_valid_ipv4( $record->{'exchange'} ) ) {
            return 0, 'IP addresses are not allowable exchange values.';
        }

        if ( !_is_valid_hostname( $record->{'exchange'} ) && !_is_valid_hostname_label( $record->{'exchange'} ) ) {
            return 0, 'Supplied exchange for MX record is invalid';
        }

        if ( $record->{'preference'} !~ m/\A\d+\z/ ) {
            return 0, 'Supplied preference for MX record is invalid.';
        }

        if ( $record->{'preference'} > 65535 ) {    # per RFC 974, a preference is an unsigned 16 bit integer
            return 0, 'Supplied preference for MX record is out of range.';
        }

        _keep_only_relevant_keys( $record, 'exchange', 'preference' );
        return 1;
    },
    'PTR' => sub {
        my $record = shift;
        if (   !_is_valid_hostname_label( $record->{'ptrdname'} )
            && !_is_valid_hostname( $record->{'ptrdname'} ) ) {
            return 0, 'Supplied ptrdname is invalid.';
        }
        return 1;
    },
    'SRV' => sub {
        my $record = shift;

        if ( !_is_valid_hostname( $record->{'target'} ) && !_is_valid_hostname_label( $record->{'target'} ) ) {
            return 0, 'Supplied target for SRV record is invalid';
        }

        if ( Cpanel::Validate::IP::is_valid_ipv6( $record->{'target'} ) ) {
            return 0, 'Supplied target can not point to an IPv6 address';
        }

        if ( Cpanel::Validate::IP::v4::is_valid_ipv4( $record->{'target'} ) ) {
            return 0, 'Supplied target can not point to an IPv4 address';
        }

        if ( !( $record->{'port'} >= 0 && $record->{'port'} <= 65535 ) ) {
            return 0, 'Supplied port for SRV record is out of range.';
        }

        if ( !( $record->{'weight'} >= 0 && $record->{'weight'} <= 65535 ) ) {
            return 0, 'Supplied weight for SRV record is out of range.';
        }

        if ( !( $record->{'priority'} >= 0 && $record->{'priority'} <= 65535 ) ) {
            return 0, 'Supplied priority for SRV record is out of range.';
        }

        _keep_only_relevant_keys( $record, 'priority', 'weight', 'port', 'target' );
        return 1;
    },
    'TXT' => sub {
        my $record = shift;
        my $old_txtdata;

        if ( !exists $record->{'txtdata'} ) {
            return 0, 'No value supplied for TXT record.';
        }

        #Encode the data unless the caller specifically requested that
        #the data remain unencoded.
        #
        if ( !$record->{'unencoded'} ) {

            if ( $record->{'txtdata'} !~ m/\A\".*\"\z/ ) {
                $old_txtdata = $record->{'txtdata'};
                $record->{'txtdata'} = Cpanel::DnsUtils::RR::encode_and_split_dns_txt_record_value( $record->{'txtdata'} );
            }

            #NOTE: Previously there was validation logic here,
            #which made some sense when we didn't parse multiple strings
            #out of TXT records. Per RFC 1035, though, it doesn't actually
            #seem possible to have an invalid TXT value section; even
            #something like:
            #
            #   "haha \013 '
            #
            #...can be validly parsed per the RFC.
        }

        _keep_only_relevant_keys( $record, 'txtdata', 'unencoded' );
        return 1;
    },
    'CAA' => sub {
        my $record = shift;

        # CPANEL-33976: The non-zero value for this is 128 because this implementation originally conflated the idea
        # of the Flags field with the specific Issuer Critical Flag defined as a part of that field. Worse, the
        # RFC-defined bit is the most significant bit, so having Issuer Critical Flag set to 1 (and all else set
        # to 0) corresponds to a Flags of 128 (where this implementation originally set that to 1). Since dis-
        # entangling the field from the individual flags will require UI changes, these are deferred to a future
        # time where the CAA record defines additional bits inside the Flags field.
        if ( exists $record->{'flag'} && $record->{'flag'} =~ m/\A(0|128)\z/ ) {
            my $critical_flag = $1;

            if ( !exists $record->{'tag'} || $record->{'tag'} !~ /\A[A-Za-z0-9]{1,15}\z/ ) {
                return 0, 'Supplied “tag” value for CAA record is invalid';
            }
            if ( $critical_flag && $record->{'tag'} !~ m/\A(?:issue|issuewild|iodef)\z/ ) {
                return 0, 'Supplied “tag” value for CAA record is invalid';
            }

            my $valid_value = 0;
            if ( $record->{'tag'} eq 'issue' || $record->{'tag'} eq 'issuewild' ) {
                $valid_value = 1 if ( $record->{'value'} eq ';' || _is_valid_hostname( $record->{'value'} ) );
            }
            elsif ( $record->{'tag'} eq 'iodef' && $record->{'value'} =~ /\Amailto:(.*)\z/ ) {
                my $address = $1;
                require Cpanel::Validate::EmailRFC;
                $valid_value = Cpanel::Validate::EmailRFC::is_valid($address);
            }
            elsif ( $record->{'tag'} eq 'iodef' ) {
                require Data::Validate::URI;
                $valid_value = Data::Validate::URI::is_web_uri( $record->{'value'}, { 'domain_disable_tld_validation' => 1 } );
            }
            elsif ( $record->{'value'} =~ /[^ \t]/ && $record->{'value'} !~ tr/\n// ) {

                # prevents misparsing as multiple resource records
                $valid_value = 1;
            }

            unless ($valid_value) {
                return ( 0, "Supplied “$record->{'tag'}” value for CAA record is invalid" );
            }
        }
        else {
            return 0, 'Supplied “flag” value for CAA record is invalid';
        }

        _keep_only_relevant_keys( $record, 'flag', 'tag', 'value' );
        return 1;
    },
);

sub _base_record_is_valid {
    my $record = shift;
    my @issues;
    if ( 255 <= length $record->{'name'} ) {
        push @issues, 'Provided name is too long.';
    }
    if ( !_is_valid_dns_label( $record->{'name'} ) && !_is_valid_dns_domain( $record->{'name'} ) ) {
        push @issues, 'Invalid name provided.';
    }
    if ( $record->{'name'} =~ m/.\*/ ) {    # asterisk must be the leftmost character if present
        push @issues, 'Contains a malformed wildcard name.';
    }

    if ( exists $record->{'class'} && $record->{'class'} !~ m/\A(?:IN|CS|CH|HS)\z/ ) {
        push @issues, 'Invalid class specified.';
    }

    if ( exists $record->{'ttl'} ) {
        if ( $record->{'ttl'} !~ m/\A[0-9]+\z/ ) {
            push @issues, 'Bad TTL provided.';
        }
        if ( 2147483647 < $record->{'ttl'} ) {
            push @issues, 'Provided TTL exceeds the maximum allowed value.';
        }
    }

    if ( $record->{'type'} !~ m/\A(?:A|AAAA|CAA|CNAME|MX|PTR|SRV|TXT|NS)\z/ ) {
        push @issues, 'Unsupported record type provided.';
    }

    return 1 if !scalar @issues;
    return 0, join ' ', @issues;
}

sub sanitize_record {
    my $record = shift;
    my ( $result, $msg );

    if ( exists $record_sanitizer_for_type{ $record->{'type'} } ) {
        ( $result, $msg ) = _base_record_is_valid($record);

        if ($result) {
            ( $result, $msg ) = $record_sanitizer_for_type{ $record->{'type'} }->($record);
        }
    }
    else {
        Cpanel::Debug::log_info( 'Whostmgr::DNS::sanitize_record: No sanitizer available for record type ' . $record->{'type'} );
        return 1;
    }

    return ( $result, 'Record Sanitized' ) if $result;
    return ( $result, 'Invalid DNS record: ' . $msg );
}

sub _resolve_record {
    my $domain = shift;
    my $address;
    eval {
        require Net::DNS::Resolver;
        my $resolver = Net::DNS::Resolver->new();
        if ( my $query = $resolver->query( $domain, 'A' ) ) {
            my ($answer) = $query->answer;
            $address = $answer->address;
        }
        else {
            Cpanel::Debug::log_info( 'Whostmgr::DNS::_resolve_record: failed to resolve "' . $domain . '": ' . $resolver->errorstring );
        }
    };
    return $address;
}

1;
