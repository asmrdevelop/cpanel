package Whostmgr::API::1::DNS;

# cpanel - Whostmgr/API/1/DNS.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Imports;

use Whostmgr::ACLS          ();
use Whostmgr::Authz         ();
use Whostmgr::API::1::Utils ();

use constant NEEDS_ROLE => 'DNS';

=encoding utf-8

=head1 NAME

Whostmgr::DNS::1::DNS - DNS and DNSSEC WHMAPI1 apis

=cut

sub update_reverse_dns_cache {
    my ( $args, $metadata ) = @_;

    require Cpanel::Config::ReverseDnsCache::Update;
    Cpanel::Config::ReverseDnsCache::Update::update_reverse_dns_cache();
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

sub _check_for_worker_linkage {
    my ( $metadata, $domain ) = @_;

    # If the domain owner is using a linked server, include a warning
    require Cpanel::AcctUtils::DomainOwner::Tiny;
    my $cpusername = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { default => undef } );

    if ( !$cpusername || ( Whostmgr::ACLS::hasroot() && $cpusername eq 'nobody' ) ) {

        # In the event that it is an unowned domain, like the initially created hostname
        # this will never have a linkage, and the check is not necessary.
        return $metadata;
    }

    require Cpanel::Config::LoadCpUserFile;
    my $cpuser_hr = Cpanel::Config::LoadCpUserFile::load_or_die($cpusername);
    require Cpanel::LinkedNode::Worker::GetAll;
    my @linkages = Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser($cpuser_hr);

    if ( scalar @linkages > 0 ) {
        $metadata->{'warnings'} = [ locale()->maketext( "This domain’s owner, “[_1]”, uses a linked mail node. Errors in this user’s [asis,DNS] records may corrupt the account’s use of that linkage. [output,strong,Proceed with extreme caution.]", $cpusername ) ];
    }
    return $metadata;
}

sub parse_dns_zone ( $args, $metadata, @ ) {
    my $zonename = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'zone' );

    _validate_and_authorize_zone($zonename);

    require Cpanel::DnsUtils::AskDnsAdmin;
    require Cpanel::ZoneFile::Parse;

    my $zone_text = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "GETZONE", 0, $zonename );

    my $parse_ar = Cpanel::ZoneFile::Parse::parse_string_to_b64( $zone_text, $zonename );

    $metadata->set_ok();

    return { payload => $parse_ar };
}

sub dumpzone {
    my ( $args, $metadata ) = @_;
    my $domain = $args->{'domain'};

    if ( !length $domain && exists $args->{'zone'} ) {
        $domain = $args->{'zone'};
        $domain =~ s/\.db$//g;
    }

    my $zoneref;
    if ( !length $domain ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'You must specify a zone to dump.';
    }
    elsif ( !Whostmgr::Authz::verify_domain_access($domain) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = "Access Denied, you don't seem to own $domain";
    }
    else {
        require Cpanel::Validate::Domain::Normalize;
        require Cpanel::QuickZoneFetch;
        require Cpanel::DnsUtils::Exists;
        my $normal_domain = Cpanel::Validate::Domain::Normalize::normalize($domain);
        my $zf            = Cpanel::QuickZoneFetch::fetch($normal_domain);
        if ( exists $zf->{'dnszone'} && ref $zf->{'dnszone'} && @{ $zf->{'dnszone'} } ) {
            $metadata->{'result'} = 1;
            $metadata->{'reason'} = 'Zone Serialized';
            $zoneref->{'record'}  = $zf->{'dnszone'};

            $metadata = _check_for_worker_linkage( $metadata, $normal_domain );
        }
        elsif ( !Cpanel::DnsUtils::Exists::domainexists($domain) ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = 'Zone does not exist.';
        }
        else {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = 'Failed to serialize zone file: ' . $zf->{'error'};
        }
    }

    return { 'zone' => [$zoneref] } if ($zoneref);
    return;
}

sub export_zone_files ( $args, $metadata, @ ) {
    require Cpanel::DnsUtils::Fetch;
    require Cpanel::Validate::Domain;

    my @zones = Whostmgr::API::1::Utils::get_length_required_arguments( $args, 'zone' );

    _validate_and_authorize_zone($_) for @zones;

    my $resp = Cpanel::DnsUtils::Fetch::fetch_zones( zones => \@zones );

    $_ = _to_base64_line($_) for values %$resp;

    my @payload = map {
        {
            zone     => $_,
            text_b64 => $resp->{$_},
        },
    } keys %$resp;

    $metadata->set_ok();

    return { payload => \@payload };
}

sub _convert_zone_to_domain_and_verify {
    my $hashref = shift;

    my $domain = $hashref->{'domain'};
    if ( !$domain && exists $hashref->{'zone'} ) {
        $domain = $hashref->{'zone'};
        $domain =~ s/\.db$//g;
        $hashref->{'domain'} = $domain;
        delete $hashref->{'zone'};
    }

    Whostmgr::Authz::verify_domain_access( $hashref->{'domain'} );

    return $domain;
}

sub _convert_line_to_Line {
    my $hashref = shift;
    if ( !exists $hashref->{'Line'} && exists $hashref->{'line'} ) {
        $hashref->{'Line'} = $hashref->{'line'};
        delete $hashref->{'line'};
    }
    return $hashref->{'Line'};
}

sub getzonerecord {
    my ( $args, $metadata ) = @_;

    _convert_zone_to_domain_and_verify($args);

    _convert_line_to_Line($args);

    my $record;
    require Cpanel::DnsUtils::Exists;

    #This domainexists() check may be superfluous ...
    if ( !Cpanel::DnsUtils::Exists::domainexists( $args->{'domain'} ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Zone does not exist.';
    }
    else {
        require Whostmgr::DNS;
        my ( $result, $msg ) = Whostmgr::DNS::get_zone_record( \$record, %$args );
        $metadata->{'result'} = $result ? 1 : 0;
        $metadata->{'reason'} = $msg;
        return { 'record' => [$record] } if $result;
    }
    return;
}

sub resetzone {
    my ( $args, $metadata ) = @_;
    _convert_zone_to_domain_and_verify($args);
    require Whostmgr::DNS::Rebuild;
    my ( $result, $msg ) = Whostmgr::DNS::Rebuild::restore_dns_zone_to_defaults(%$args);
    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $msg || 'OK';
    return;
}

sub addzonerecord {
    my ( $args, $metadata ) = @_;
    _convert_zone_to_domain_and_verify($args);
    require Whostmgr::DNS;
    my ( $result, $msg ) = Whostmgr::DNS::add_zone_record($args);
    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $msg || 'OK';
    return;
}

sub editzonerecord {
    my ( $args, $metadata ) = @_;
    _convert_zone_to_domain_and_verify($args);
    _convert_line_to_Line($args);
    require Whostmgr::DNS;
    my ( $result, $msg ) = Whostmgr::DNS::edit_zone_record($args);
    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $msg || 'OK';
    return;
}

sub removezonerecord {
    my ( $args, $metadata ) = @_;
    _convert_zone_to_domain_and_verify($args);
    _convert_line_to_Line($args);
    require Whostmgr::DNS;
    my ( $result, $msg ) = Whostmgr::DNS::remove_zone_record($args);
    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $msg || 'OK';
    return;
}

sub adddns {
    my ( $args, $metadata ) = @_;

    my $domain    = $args->{'domain'};
    my $trueowner = $args->{'trueowner'};
    my $ip        = $args->{'ip'};
    my $template  = $args->{'template'};
    my $ipv6      = $args->{'ipv6'};
    my $has_ipv6  = $ipv6 ? 1 : 0;

    if ( !defined $trueowner ) {
        $trueowner = $ENV{'REMOTE_USER'};
    }

    Whostmgr::Authz::verify_account_access($trueowner);

    require Cpanel::DnsUtils::Add;
    my ( $status, $statusmsg ) = Cpanel::DnsUtils::Add::doadddns(
        'domain'         => $domain,
        'ip'             => $ip,
        'trueowner'      => $trueowner,
        'allowoverwrite' => Whostmgr::ACLS::hasroot(),
        'template'       => $template,
        'has_ipv6'       => $has_ipv6,
        'ipv6'           => $ipv6,
    );

    $metadata->{'result'} = $status ? 1 : 0;
    $metadata->{'reason'} = $statusmsg;
    return;
}

sub killdns {
    my ( $args, $metadata ) = @_;

    my $domain = $args->{'domain'} or die "A domain is required.\n";
    Whostmgr::Authz::verify_domain_access($domain);

    require Whostmgr::DNS::Kill;
    my $output = Whostmgr::DNS::Kill::kill_multiple($domain);

    $metadata->{'result'}          = 1;
    $metadata->{'reason'}          = 'OK';
    $metadata->{'output'}->{'raw'} = $output;

    return;
}

sub listzones {
    my ( $args, $metadata ) = @_;
    my @data;
    require Cpanel::DnsUtils::List;
    my $domain_ref = Cpanel::DnsUtils::List::listzones( 'hasroot' => Whostmgr::ACLS::hasroot() );
    foreach my $domain (@$domain_ref) {
        push @data, { 'domain' => $domain, 'zonefile' => $domain . '.db' };
    }
    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'zone' => \@data } if scalar @data;
    return;
}

sub listmxs {
    my ( $args, $metadata ) = @_;
    my $domain = $args->{'domain'};
    Whostmgr::Authz::verify_domain_access($domain);
    my $mxs = [];
    require Whostmgr::DNS;
    my ( $result, $reason ) = Whostmgr::DNS::get_zone_records_by_type( $mxs, $domain, 'MX' );
    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $reason || ( $result ? 'OK' : 'Failed to obtain MX records.' );
    return if !scalar @$mxs;
    return { 'record' => $mxs };
}

sub savemxs {
    my ( $args, $metadata ) = @_;

    Whostmgr::Authz::verify_domain_access( $args->{'domain'} );

    my @records;
    foreach my $arg ( keys %$args ) {
        next if ( $arg !~ m/^name(.*)/ );
        my $id     = $1;
        my $record = { 'name' => $args->{$arg}, 'type' => 'MX' };
        foreach my $param (qw{preference ttl class exchange}) {
            next if !exists $args->{ $param . $id };
            $record->{$param} = $args->{ $param . $id };
        }
        push @records, $record;
    }

    my $domain = $args->{'domain'};
    my $serial = $args->{'serialnum'};
    require Whostmgr::DNS;
    my ( $result, $reason ) = Whostmgr::DNS::save_mxs( $domain, \@records, $serial );
    $metadata->{'result'} = $result ? 1 : 0;
    $metadata->{'reason'} = $reason || ( $result ? 'OK' : 'Failed to set MX records.' );
    return;
}

sub has_local_authority {

    my ( $args, $metadata ) = @_;

    require Whostmgr::API::1::Utils::Domains;
    my $domains = Whostmgr::API::1::Utils::Domains::validate_domains_or_die($args);

    require Cpanel::DnsUtils::Authority;
    my $has_authority = Cpanel::DnsUtils::Authority::has_local_authority($domains);

    $metadata->{result} = 1;
    $metadata->{reason} = "OK";

    return { records => [ map { { domain => $_, %{ $has_authority->{$_} } } } @$domains ] };
}

sub set_up_dns_resolver_workarounds {
    my ( $args, $metadata ) = @_;

    require Cpanel::DNS::Unbound::Workarounds;
    my $flags = Cpanel::DNS::Unbound::Workarounds::set_up_dns_resolver_workarounds() or do {
        die 'The system failed to find a functional recursive DNS resolver configuration. Ensure that your firewall allows bidirectional UDP and TCP with remote port 53.';
    };

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { flags => $flags };

}

=head2 enable_dnssec_for_domains

This is a thin WHMAPI1 wrapper around
C<Cpanel::DNSSEC::enable_dnssec_for_domains>

=cut

sub enable_dnssec_for_domains ( $args, $metadata, $api_info_hr ) {
    require Whostmgr::API::1::Utils::Domains;

    require Cpanel::DNSSEC;

    my $domains_ar = Cpanel::DNSSEC::enable_dnssec_for_domains(
        Whostmgr::API::1::Utils::Domains::validate_domains_or_die($args),
        {
            'use_nsec3'        => $args->{'use_nsec3'},
            'nsec3_opt_out'    => $args->{'nsec3_opt_out'},
            'nsec3_iterations' => $args->{'nsec3_iterations'},
            'nsec3_narrow'     => $args->{'nsec3_narrow'},
            'nsec3_salt'       => $args->{'nsec3_salt'},
        },
        {
            'algo_num'  => $args->{'algo_num'},
            'key_setup' => $args->{'key_setup'},
            'active'    => $args->{'active'},
        }
    );
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { domains => $domains_ar };
}

=head2 disable_dnssec_for_domains

This is a thin WHMAPI1 wrapper around
C<Cpanel::DNSSEC::disable_dnssec_for_domains>

=cut

sub disable_dnssec_for_domains ( $args, $metadata, $api_info_hr ) {
    require Whostmgr::API::1::Utils::Domains;
    my $domains = Whostmgr::API::1::Utils::Domains::validate_domains_or_die($args);
    require Cpanel::DNSSEC;

    my $domains_ar = Cpanel::DNSSEC::disable_dnssec_for_domains($domains);
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { domains => $domains_ar };
}

=head2 fetch_ds_records_for_domains

This is a thin WHMAPI1 wrapper around
C<Cpanel::DNSSEC::fetch_ds_records_for_domains>

=cut

sub fetch_ds_records_for_domains ( $args, $metadata, $api_info_hr ) {
    require Whostmgr::API::1::Utils::Domains;
    my $domains = Whostmgr::API::1::Utils::Domains::validate_domains_or_die($args);
    require Cpanel::DNSSEC;

    my $domains_ar = Cpanel::DNSSEC::fetch_ds_records_for_domains($domains);
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { domains => $domains_ar };
}

=head2 set_nsec3_for_domains

This is a thin WHMAPI1 wrapper around
C<Cpanel::DNSSEC::set_nsec3_for_domains>

=cut

sub set_nsec3_for_domains ( $args, $metadata, $api_info_hr ) {

    require Whostmgr::API::1::Utils::Domains;

    require Cpanel::DNSSEC;
    my $domains_ar = Cpanel::DNSSEC::set_nsec3_for_domains(
        Whostmgr::API::1::Utils::Domains::validate_domains_or_die($args),
        {
            'nsec3_opt_out'    => Whostmgr::API::1::Utils::get_length_required_argument( $args, 'nsec3_opt_out' ),
            'nsec3_iterations' => Whostmgr::API::1::Utils::get_length_required_argument( $args, 'nsec3_iterations' ),
            'nsec3_narrow'     => Whostmgr::API::1::Utils::get_length_required_argument( $args, 'nsec3_narrow' ),
            'nsec3_salt'       => Whostmgr::API::1::Utils::get_length_required_argument( $args, 'nsec3_salt' ),
        }
    );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { domains => $domains_ar };
}

=head2 unset_nsec3_for_domains

This is a thin WHMAPI1 wrapper around
C<Cpanel::DNSSEC::unset_nsec3_for_domains>

=cut

sub unset_nsec3_for_domains ( $args, $metadata, $api_info_hr ) {

    require Whostmgr::API::1::Utils::Domains;

    my $domains = Whostmgr::API::1::Utils::Domains::validate_domains_or_die($args);

    require Cpanel::DNSSEC;
    my $domains_ar = Cpanel::DNSSEC::unset_nsec3_for_domains($domains);
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { domains => $domains_ar };
}

=head2 activate_zone_key

This is a thin WHMAPI1 wrapper around
C<Cpanel::DNSSEC::activate_zone_key>

=cut

sub activate_zone_key ( $args, $metadata, $api_info_hr ) {
    my $domain = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'domain' );
    my $key_id = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'key_id' );
    Whostmgr::Authz::verify_domain_access($domain);
    require Cpanel::DNSSEC;

    my $result = Cpanel::DNSSEC::activate_zone_key( $domain, $key_id );

    _set_metadata_and_reduce( $metadata, $result );

    return undef;
}

=head2 deactivate_zone_key

This is a thin WHMAPI1 wrapper around
C<Cpanel::DNSSEC::deactivate_zone_key>

=cut

sub deactivate_zone_key ( $args, $metadata, $api_info_hr ) {
    my $domain = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'domain' );
    my $key_id = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'key_id' );
    Whostmgr::Authz::verify_domain_access($domain);
    require Cpanel::DNSSEC;

    my $result = Cpanel::DNSSEC::deactivate_zone_key( $domain, $key_id );

    _set_metadata_and_reduce( $metadata, $result );

    return undef;
}

=head2 add_zone_key

This is a thin WHMAPI1 wrapper around
C<Cpanel::DNSSEC::add_zone_key>

=cut

sub add_zone_key ( $args, $metadata, $api_info_hr ) {
    my $domain = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'domain' );
    Whostmgr::Authz::verify_domain_access($domain);
    require Cpanel::DNSSEC;

    my $result = Cpanel::DNSSEC::add_zone_key(
        $domain,
        {
            'algo_num' => Whostmgr::API::1::Utils::get_length_required_argument( $args, 'algo_num' ),
            'key_type' => Whostmgr::API::1::Utils::get_length_required_argument( $args, 'key_type' ),
            'key_size' => $args->{'key_size'},
            'active'   => $args->{'active'},
        }
    );

    return _set_metadata_and_reduce( $metadata, $result, 'new_key_id' );
}

=head2 remove_zone_key

This is a thin WHMAPI1 wrapper around
C<Cpanel::DNSSEC::remove_zone_key>

=cut

sub remove_zone_key ( $args, $metadata, $api_info_hr ) {
    my $domain = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'domain' );
    my $key_id = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'key_id' );
    Whostmgr::Authz::verify_domain_access($domain);
    require Cpanel::DNSSEC;

    my $result = Cpanel::DNSSEC::remove_zone_key( $domain, $key_id );

    _set_metadata_and_reduce( $metadata, $result );

    return undef;
}

=head2 import_zone_key

This is a thin WHMAPI1 wrapper around
C<Cpanel::DNSSEC::import_zone_key>

=cut

sub import_zone_key ( $args, $metadata, $api_info_hr ) {
    my $domain   = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'domain' );
    my $key_data = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'key_data' );
    my $key_type = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'key_type' );

    Whostmgr::Authz::verify_domain_access($domain);
    require Cpanel::DNSSEC;

    my $result = Cpanel::DNSSEC::import_zone_key( $domain, $key_data, $key_type );

    return _set_metadata_and_reduce( $metadata, $result, 'new_key_id' );
}

=head2 export_zone_key

This is a thin WHMAPI1 wrapper around
C<Cpanel::DNSSEC::export_zone_key>

=cut

sub export_zone_key ( $args, $metadata, $api_info_hr ) {
    my $domain = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'domain' );
    my $key_id = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'key_id' );
    Whostmgr::Authz::verify_domain_access($domain);
    require Cpanel::DNSSEC;

    my $result = Cpanel::DNSSEC::export_zone_key( $domain, $key_id );

    return _set_metadata_and_reduce( $metadata, $result, 'key_tag', 'key_type', 'key_content' );
}

=head2 export_zone_dnskey

This is a thin WHMAPI1 wrapper around
C<Cpanel::DNSSEC::export_zone_dnskey>

=cut

sub export_zone_dnskey ( $args, $metadata, $api_info_hr ) {
    my $domain = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'domain' );
    my $key_id = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'key_id' );
    Whostmgr::Authz::verify_domain_access($domain);
    require Cpanel::DNSSEC;

    my $result = Cpanel::DNSSEC::export_zone_dnskey( $domain, $key_id );

    return _set_metadata_and_reduce( $metadata, $result, 'key_id', 'dnskey' );
}

=head2 mass_edit_dns_zone

L<https://go.cpanel.net/mass_edit_dns_zone>

NB: This API returns { type => 'Stale' } in its payload in the event of
a serial number mismatch.

=cut

sub mass_edit_dns_zone ( $args, $metadata, @ ) {
    require Cpanel::APICommon::DNS;

    # To avoid trying to support arbitrary record types, we
    # limit creation to types we know we can support.
    state %_ACCEPTED_ZONE_TYPE_LOOKUP = map { $_ => undef } (
        'A',
        'AAAA',
        'AFSDB',
        'CAA',
        'CNAME',
        'DNAME',
        'DS',
        'HINFO',
        'LOC',
        'MX',
        'NAPTR',
        'NS',
        'PTR',
        'RP',
        'SRV',
        'TLSA',
        'TXT',
    );

    require Cpanel::ZoneFile::LineEdit;

    my $zone   = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'zone' );
    my $serial = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'serial' );

    my @additions = Whostmgr::API::1::Utils::get_length_arguments( $args, 'add' );
    my @edits     = Whostmgr::API::1::Utils::get_length_arguments( $args, 'edit' );
    my @removals  = Whostmgr::API::1::Utils::get_length_arguments( $args, 'remove' );

    _validate_and_authorize_zone($zone);

    if ( !@additions && !@edits && !@removals ) {
        $metadata->set_not_ok( locale()->maketext('You must provide at least one change to the [asis,DNS] zone.') );
        return;
    }

    require Cpanel::JSON;
    $_ = Cpanel::JSON::Load($_) for ( @additions, @edits );

    for my $lineidx (@removals) {
        if ( my $err = Cpanel::APICommon::DNS::get_mass_edit_remove_error($lineidx) ) {
            $metadata->set_not_ok($err);
            return;
        }
    }

    for my $add_item (@additions) {
        if ( my $err = Cpanel::APICommon::DNS::get_mass_edit_add_error($add_item) ) {
            $metadata->set_not_ok($err);
            return;
        }

        if ( !exists $_ACCEPTED_ZONE_TYPE_LOOKUP{ $add_item->{'record_type'} } ) {
            my @accepted = sort keys %_ACCEPTED_ZONE_TYPE_LOOKUP;
            $metadata->set_not_ok( locale()->maketext( 'This interface cannot create “[_1]” records. It can only create [list_and,_2] records.', $add_item->{'record_type'}, \@accepted ) );
            return;
        }

        # Convert to the format that the update backend expects:
        $add_item = [
            @{$add_item}{ 'dname', 'ttl', 'record_type' },
            $add_item->{'data'}->@*,
        ];
    }

    for my $edit_item (@edits) {
        if ( my $err = Cpanel::APICommon::DNS::get_mass_edit_edit_error($edit_item) ) {
            $metadata->set_not_ok($err);
            return;
        }

        $edit_item = [
            @{$edit_item}{ 'line_index', 'dname', 'ttl', 'record_type' },
            $edit_item->{'data'}->@*,
        ];
    }

    my $editor;

    my $typed_err;

    require Cpanel::Try;
    Cpanel::Try::try(
        sub {
            $editor = Cpanel::ZoneFile::LineEdit->new(
                zone   => $zone,
                serial => $serial,
            );
        },
        'Cpanel::Exception::Stale' => sub ($err) {
            $metadata->set_not_ok( $err->to_string_no_id() );

            require Cpanel::APICommon::Error;
            $typed_err = Cpanel::APICommon::Error::convert_to_payload('Stale');
        },
    );

    return $typed_err if $typed_err;

    $editor->add(@$_)   for @additions;
    $editor->edit(@$_)  for @edits;
    $editor->remove($_) for @removals;

    my $new_serial;

    Cpanel::Try::try(
        sub { $new_serial = $editor->save() },
        'Cpanel::Exception::DNS::InvalidZoneFile' => sub ($err) {
            $metadata->set_not_ok( $err->to_string_no_id() );

            require Cpanel::APICommon::Error;
            $typed_err = Cpanel::APICommon::Error::convert_to_payload(
                'InvalidZoneFile',
                by_line => $err->get_by_line_utf8(),
            );
        },
    );

    return $typed_err if $typed_err;

    $metadata->set_ok();

    return { new_serial => $new_serial };
}

#----------------------------------------------------------------------

=head1 PRIVATE API FUNCTIONS

=cut

=head2 PRIVATE_check_zone_file( zone => $name )

Takes a C<zone> (name, e.g., C<example.com>) and returns a hashref
with a C<payload> that’s an arrayref. Each item in that array is
a hashref:

=over

=item * C<line> - The line number (1-indexed) of the error.

=item * C<text_b64> - The description of the error, encoded to base64.

(B<IMPORTANT:> The base64-decoded value may include B<non-UTF-8> values.)

=back

NB: This function is internal because it assumes that the system stores DNS
zones as RFC 1035 master files. While that’s our status quo as of early 2021,
we want to abstract that implementation detail from integrators as much as
possible.

=cut

sub PRIVATE_check_zone_file ( $args, $metadata, @ ) {
    require Cpanel::DnsUtils::CheckZone;
    require Cpanel::DnsUtils::Fetch;

    my $zonename = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'zone' );

    _validate_and_authorize_zone($zonename);

    my $zone_text_hr = Cpanel::DnsUtils::Fetch::fetch_zones(
        zones => [$zonename],
    );

    my $errs_ar = Cpanel::DnsUtils::CheckZone::check_zone(
        %$zone_text_hr,
    );

    for my $err (@$errs_ar) {
        $err = {
            line     => $err->[0],
            text_b64 => _to_base64_line( $err->[1] ),
        };
    }

    $metadata->set_ok();

    return { payload => $errs_ar };
}

sub _validate_and_authorize_zone ($zonename) {
    require Cpanel::Validate::Domain;

    Cpanel::Validate::Domain::valid_rfc_domainname_or_die($zonename);
    Whostmgr::Authz::verify_domain_existence_and_access($zonename);

    return;
}

sub _to_base64_line ($text) {
    require Cpanel::Base64;

    return Cpanel::Base64::encode_to_line($text);
}

#----------------------------------------------------------------------

sub _set_metadata_and_reduce ( $metadata, $result, @keys ) {
    if ( !$result->{'success'} ) {
        $metadata->set_not_ok( $result->{'error'} );
        return undef;
    }

    $metadata->set_ok();

    return { %{$result}{@keys} };
}

1;
