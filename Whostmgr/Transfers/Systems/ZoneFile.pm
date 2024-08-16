package Whostmgr::Transfers::Systems::ZoneFile;

# cpanel - Whostmgr/Transfers/Systems/ZoneFile.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

# RR Audit: JNK

use base qw(
  Whostmgr::Transfers::Systems
);

use Cpanel::Config::userdata::Load             ();
use Cpanel::LoadFile                           ();
use Cpanel::IP::Loopback                       ();
use Cpanel::Exception                          ();
use Cpanel::Config::LoadCpUserFile             ();
use Cpanel::Config::LoadUserDomains            ();
use Cpanel::Config::LoadWwwAcctConf            ();
use Cpanel::FileUtils::Dir                     ();
use Cpanel::DnsUtils::AskDnsAdmin              ();
use Cpanel::DnsUtils::Fetch                    ();
use Cpanel::DnsUtils::Install                  ();
use Cpanel::NAT                                ();
use Cpanel::Time                               ();
use Cpanel::Validate::Domain::Normalize        ();
use Cpanel::Validate::IP                       ();
use Cpanel::ZoneFile                           ();
use Cpanel::ZoneFile::Utils                    ();
use Cpanel::IP::Convert                        ();
use Whostmgr::Transfers::State                 ();
use Cpanel::DnsUtils::Fetch                    ();
use Cpanel::Config::ModCpUserFile              ();
use Cpanel::FileUtils::Lines                   ();
use Cpanel::AcctUtils::Owner                   ();
use Cpanel::DIp::IsDedicated                   ();
use Whostmgr::DNS::SwapIP                      ();
use Whostmgr::Ips::Shared                      ();
use Whostmgr::Transfers::Utils::WorkerNodesObj ();

use Try::Tiny;

sub get_phase { return 75; }    # Must happen after Vhosts but before PostRestoreActions

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores custom [output,abbr,DNS,Domain Name System] Zone entries.') ];
}

sub get_restricted_available {
    return 1;
}

our $MAX_ZONEFILE_SIZE_BYTES = ( 1024**2 * 32 );    #  32 MiB

# get IPv6 address from /etc/wwwacct.conf, if any
our $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
our $ADDR6       = $wwwacct_ref->{'ADDR6'} // undef;

# Our for tests
# Update get_merge_comment_regex if this changes
our $MERGE_COMMENT = 'Previous value removed by cPanel ' . ( Whostmgr::Transfers::State::is_transfer() ? 'transfer' : 'restore' ) . ' auto-merge on ' . Cpanel::Time::time2condensedtime() . ' GMT';
our $MERGE_COMMENT_REGEX;
our $MAX_COMMENT_AGE = ( 86400 * 30 );    # 30 days in seconds

# Update this if $MERGE_COMMENT changes
sub get_merge_comment_regex {
    return ( $MERGE_COMMENT_REGEX ||= qr/cPanel (?:transfer|restore) auto-merge on ([\d]+) GMT/ );
}

#REQUIRED:
#userdata
#NOTE: optional 'pre_dns_restore' coderef
#NOTE: optional 'mergeip' - either 'all' (default) or 'basic'
#NOTE: optional 'restoresubs' flag
sub unrestricted_restore {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ($self) = @_;

    my $username = $self->{'_utils'}->local_username();

    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load($username);
    my $ftpip      = Cpanel::NAT::get_public_ip( Cpanel::DIp::IsDedicated::isdedicatedip( $cpuser_ref->{'IP'} ) ? $cpuser_ref->{'IP'} : Whostmgr::Ips::Shared::get_shared_ip_address_for_creator( Cpanel::AcctUtils::Owner::getowner($username) ) );
    my $new_ip     = Cpanel::NAT::get_public_ip( $cpuser_ref->{'IP'} );

    my ( $ok, $data ) = $self->{'_archive_manager'}->get_raw_cpuser_data_from_archive();
    $self->warn($data) if !$ok;
    my $previous_ip = $data && Cpanel::Validate::IP::is_valid_ip( $data->{'IP'} ) && $data->{'IP'};

    $previous_ip = undef if $previous_ip && Cpanel::IP::Loopback::is_loopback($previous_ip);    # workaround a NAT bug from older version

    my @related_ips = $self->_get_related_ips();

    my @domains = $self->{'_utils'}->domains();

    my %changezoneip_calls;
    my %restored_domains = map { $_ => 1 } @domains;
    my %original_domains = map { $_ => 1 } @{ $self->{'_utils'}->get_original_domains() };
    my $userdomains_ref;

    $self->start_action('Restoring DNS zones');

    my $extractdir = $self->extractdir();

    my ( $err, $zone_files_ar );
    try {
        $zone_files_ar = Cpanel::FileUtils::Dir::get_directory_nodes("$extractdir/dnszones");
    }
    catch {
        $err = $_;
    };
    return ( 0, Cpanel::Exception::get_string($err) ) if $err;

    my $replaceip = $self->{'_utils'}->{'flags'}->{'replaceip'} || 'all';

    my %zone_updates;

    # In case a reseller was restored in the same process
    # we need to reload static domains for swapip
    Whostmgr::DNS::SwapIP::reset_static_domains();
    #
    #
    $self->start_action( $self->_locale()->maketext("Fetching existing zones.") );
    my $zone_map_ref = Cpanel::DnsUtils::Fetch::fetch_zones( 'zones' => [ keys %restored_domains ], 'flags' => $Cpanel::DnsUtils::AskDnsAdmin::LOCAL_ONLY );

  ZONE:
    foreach my $file ( sort @$zone_files_ar ) {
        my $zone           = $file;
        my $zone_file_path = "$extractdir/dnszones/$file";

        $zone =~ s/\.db$//g;
        $zone = Cpanel::Validate::Domain::Normalize::normalize($zone);

        if ( !$restored_domains{$zone} ) {
            if ( !$original_domains{$zone} ) {
                $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system could not restore the zone “[_1]” because it does not match any domain on this account.', $zone ) );
                next;
            }

            $userdomains_ref ||= Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );

            # Probably added via WHM's Add a DNS Zone.  Ensure that we're not
            # overwriting someone else's zone.
            if ( $userdomains_ref->{$zone} && $userdomains_ref->{$zone} ne $username ) {
                $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The system could not restore the zone “[_1]” because it is controlled by the user “[_2]”.', $zone, $userdomains_ref->{$zone} ) );
                next;
            }
        }

        $self->start_action( $self->_locale()->maketext( "Restoring zone: “[_1]”.", $zone ) );

        my $custom_zone_obj = $self->_load_zone_file_as_object( $zone, $zone_file_path ) or next ZONE;

        # Remove any old auto-merge comments that may be hanging around to keep more comments from building
        _remove_old_automerge_comments($custom_zone_obj);

        if ( $zone_map_ref->{$zone} ) {
            my $current_zone_obj = Cpanel::ZoneFile->new( 'domain' => $zone, 'text' => $zone_map_ref->{$zone} );

            # custom_zone_obj will be modified by these calls
            # The only way for these methods to fail currently is if Cpanel::ZoneFile incorrectly parsed the lines in the zone
            # If this happens, the zone should fail to validate below.
            $self->_merge_records( $zone, $custom_zone_obj, $current_zone_obj );
        }

        if ( !$restored_domains{$zone} && $original_domains{$zone} ) {

            # Probably added via WHM's Add a DNS Zone.  Above, w ensure that we're not
            # overwriting someone else's zone.
            $self->_attach_zone_to_user( $zone, $username );
        }

        foreach my $commented_record ( $custom_zone_obj->comment_out_cname_conflicts($MERGE_COMMENT) ) {
            $self->{'_utils'}->warn( $self->_locale()->maketext( 'The system disabled a [asis,CNAME] record for “[_1]” due to a conflict.', $commented_record, $zone ) );
        }

      HANDLE_IPv6:
        if ( not $ADDR6 and @related_ips ) {    # only removes addresses contained in @related_ips, so keeps unrelated IPv6 addresses (presumably external servers)
            $custom_zone_obj->_remove_IPv6_records_by_address( 'ipv6_addresses_to_remove' => \@related_ips );
        }
        elsif (@related_ips) {                  # replace all @related_ips in AAAA record with ADDR6; dedicated IPv6 addressing during transfer is not yet supported
            $custom_zone_obj->_swap_IPv6_records_by_address( 'ipv6_addresses_to_replace' => \@related_ips, 'new_ipv6' => $ADDR6 );
        }

        #done merging NS lines
        # only used if no ip can be guessed from the previous user configuration file
        # when transferring from a NAT server we also need to be sure to use the correct IP and not a local one to the remote
        #
        # CPANEL-23647:
        # We used to ignore the $previous_ip value if it was not in the zone file, however that is a
        # perfectly valid scenario since cPanel could only be hosting the dns for the domain
        # and the site is actually hosted elsewhere.
        $previous_ip ||= Whostmgr::DNS::SwapIP::get_sourceip_from_zonefile_obj($custom_zone_obj);

        if ( !length $previous_ip ) {

            # Its very unlikely that we would ever get here now that we validate the previous custom
            # zone looks sane.
            $self->warn("The system could not determine the previous IP address for the zone “$zone” because there was no “IP” entry in the cPanel users file, and the zone lacked an “A” record for “$zone”… The zone will be restored without updating the previous IP address to the account’s current IP address.");

        }

        if ( my @previous_and_related_not_new_ftp_ips = grep { $_ ne $new_ip || $_ ne $ftpip } ( $previous_ip, @related_ips ) ) {
            Whostmgr::DNS::SwapIP::swap_zonefile_obj_ips(
                'sourceips_hr'  => { map { Cpanel::NAT::get_public_ip($_) => 1 } @previous_and_related_not_new_ftp_ips },
                'zone_file_obj' => $custom_zone_obj,
                'ftpip'         => $ftpip,
                'destip'        => $new_ip,
                'replaceip'     => $replaceip
            );
        }

        $custom_zone_obj->increase_serial_number();

        my $ns_records = $custom_zone_obj->find_records( 'type' => 'NS' );
        if ( !$ns_records ) {
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'Because the NS records are missing, the system could not restore the zone for the domain “[_1]”.', $zone ) );
            next ZONE;
        }

        $self->utils()->set_ns_records_for_zone( $zone, $ns_records );

        $self->_update_exchange_for_hostname($custom_zone_obj);

        $zone_updates{$zone} = $custom_zone_obj->to_zone_string();
    }

    # Account TRANSFERS do local only because a DNS cluster sync
    # happens at the end of the restoration in PublishZones
    if ( scalar keys %zone_updates ) {
        my @zone_list  = sort keys %zone_updates;
        my $_dns_local = Whostmgr::Transfers::State::is_transfer() ? $Cpanel::DnsUtils::AskDnsAdmin::LOCAL_ONLY : $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL;
        $self->start_action( $_dns_local ? $self->_locale()->maketext( "Local Zone Updates: [list_and_quoted,_1]", \@zone_list ) : $self->_locale()->maketext( "Cluster Zone Updates: [list_and_quoted,_1]", \@zone_list ) );
        my %http_query = map { ( "cpdnszone-$_" => $zone_updates{$_} ) } @zone_list;
        Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin(
            'SYNCZONES',
            $_dns_local, q{}, q{}, q{},
            \%http_query,
        );
    }

    # Zones will be reloaded in SendZonesToCluster

    #TODO: Can this just run anyway?
    if ( $self->{'restoresubs'} ) {
        my $subs_ar = Cpanel::Config::userdata::Load::get_subdomains($username) or do {

            #TODO: error handling
        };

        $self->start_action('Adding missing subdomain DNS entries (if needed)');
        _add_missing_subdomain_dns_entries( $subs_ar, $new_ip );

    }

    return 1;
}

sub _update_exchange_for_hostname {
    my ( $self, $zone_obj ) = @_;

    my $extractdir = $self->extractdir();

    my $old_mx = Whostmgr::Transfers::Utils::WorkerNodesObj->new($extractdir)->get_type_hostname('Mail');

    $old_mx ||= $self->archive_manager()->get_hostname();

    # If we didn’t get a hostname from the archive itself, then see if
    # we are in a transfer session that stored a remote hostname.
    $old_mx ||= $self->utils()->{'flags'}{'remote_hostname'};

    # This will need to be smarter if we implement restores to
    # remote-Mail setups.
    my $new_mx = Cpanel::Sys::Hostname::gethostname();

    if ( $old_mx && $old_mx ne $new_mx ) {
        require Cpanel::Sys::Hostname;

        require Cpanel::ZoneFile::MigrateMX;

        Cpanel::ZoneFile::MigrateMX::migrate(
            $zone_obj,
            $old_mx => $new_mx,
        );
    }

    return;
}

sub _validate_zone_data {
    my ( $domain, $zone_data ) = @_;

    my $zone = Cpanel::ZoneFile->new( 'domain' => $domain, 'text' => $zone_data );
    return ( 0, 'The supplied zone data does not parse.' )                 if !$zone;
    return ( 0, $zone->{'error'} )                                         if $zone->{'error'};
    return ( 0, 'The supplied zone data does not contain an SOA record.' ) if !grep { $_->{'type'} eq 'SOA' } @{ $zone->{'dnszone'} };

    return ( 1, $zone );
}

*restricted_restore = \&unrestricted_restore;

####################################################################################
#
# Methods:
#   _merge_${dns_record_type}${optional_suffix}
#
# Description:
#   The following replace functions are meant to overwrite records with certain types
#   in the incoming transferred/restored zonefile, $custom_zone_obj, with those that
#   were created when the account was created earlier in the transfer/restore process by
#   the DNS template system, $current_zone_obj.
#
#   NOTE: These replace functions do not replace EVERYTHING in the incoming zone file with
#         those in the template, only certain record types in the zonefile's default ORIGIN.
#
#   NOTE2: Please also note that these functions do NOT do CNAME conflict resolution. See
#          Cpanel::ZoneFile::Utils::comment_out_cname_conflicts for that functionality.
#
# Parameters:
#   $self             - this object
#   $domain           - The domain name of the zonefile. This limits the scope of the replace to only the
#                       zonefile's default ORIGIN.
#   $custom_zone_obj  - The incoming transferred/restored zonefile as a Cpanel::ZoneFile obj.
#   $current_zone_obj - The zonefile created by the DNS template system during account creation as a
#                       Cpanel::ZoneFile obj.
#
# Exceptions:
#   None currently.
#
# Returns;
#   Two-arg return.
#   $status - 0 for failure, 1 for success
#   $error  - error message
#
sub _merge_mx_record_with_zero_preference {
    my ( $self, $domain, $custom_zone_obj, $current_zone_obj ) = @_;

    my $filter_cr = sub {
        my ($record) = @_;

        return 1 if defined $record->{'preference'} && $record->{'preference'} == 0;
        return 0;
    };

    # If the local dns template has an the MX entry to "domain.com" or a subdomain of "domain.com"
    # we prefer the MX records that are coming in from the transfer as they likely have
    # configured a remote mail server.
    my $prefer_transferred_records_cr = sub {
        my ($template_records_ref) = @_;

        foreach my $record ( @{$template_records_ref} ) {
            if ( defined $record->{'exchange'} && ( $record->{'exchange'} =~ /(^|\.)$domain$/ ) ) {
                return 1;
            }
        }
        return 0;
    };

    return $self->_merge_records_of_types(
        {
            'custom_zone_obj'            => $custom_zone_obj,
            'current_zone_obj'           => $current_zone_obj,
            'resource_types'             => ['MX'],
            'resource_names'             => [ $domain . '.' ],
            'filter'                     => $filter_cr,
            'prefer_transferred_records' => $prefer_transferred_records_cr,
        }
    );
}

# For non-ftp records
sub _use_transferred_records_if_they_exist {
    my ( $template_records_ref, $transfered_records_ref ) = @_;

    return $transfered_records_ref && @{$transfered_records_ref} ? 1 : 0;
}

# Ftp records are special since they use an alternate ip
sub _use_transferred_records_if_they_exist_and_are_not_cnames {
    my ( $template_records_ref, $transfered_records_ref ) = @_;
    return $transfered_records_ref && @{$transfered_records_ref} && ( grep { $_->{'address'} } @{$transfered_records_ref} ) ? 1 : 0;
}

# main domain A and AAAA
sub _merge_main_domain_a_records {
    my ( $self, $domain, $custom_zone_obj, $current_zone_obj ) = @_;

    return $self->_merge_records_of_types(
        {
            'custom_zone_obj'            => $custom_zone_obj,
            'current_zone_obj'           => $current_zone_obj,
            'resource_types'             => [ 'A', 'AAAA', 'CNAME' ],
            'resource_names'             => [ $domain . '.', '*.' . $domain . '.' ],
            'prefer_transferred_records' => \&_use_transferred_records_if_they_exist,
        }
    );
}

sub _merge_ftp_records {
    my ( $self, $domain, $custom_zone_obj, $current_zone_obj ) = @_;

    return $self->_merge_records_of_types(
        {
            'custom_zone_obj'            => $custom_zone_obj,
            'current_zone_obj'           => $current_zone_obj,
            'resource_types'             => [ 'A', 'AAAA', 'CNAME' ],
            'resource_names'             => [ 'ftp.' . $domain . '.' ],
            'prefer_transferred_records' => \&_use_transferred_records_if_they_exist_and_are_not_cnames,
        }
    );
}

sub _merge_www_records {
    my ( $self, $domain, $custom_zone_obj, $current_zone_obj ) = @_;

    return $self->_merge_records_of_types(
        {
            'custom_zone_obj'            => $custom_zone_obj,
            'current_zone_obj'           => $current_zone_obj,
            'resource_types'             => [ 'A', 'AAAA', 'CNAME' ],
            'resource_names'             => [ 'www.' . $domain . '.', '*.' . $domain . '.' ],
            'prefer_transferred_records' => \&_use_transferred_records_if_they_exist,
        }
    );
}

sub _merge_mail_records {
    my ( $self, $domain, $custom_zone_obj, $current_zone_obj ) = @_;

    return $self->_merge_records_of_types(
        {
            'custom_zone_obj'            => $custom_zone_obj,
            'current_zone_obj'           => $current_zone_obj,
            'resource_types'             => [ 'A', 'AAAA', 'CNAME' ],
            'resource_names'             => [ 'mail.' . $domain . '.', '*.' . $domain . '.' ],
            'prefer_transferred_records' => sub {
                my ( $template_records_ref, $transfered_records_ref ) = @_;

                # Special case for restores of accounts that were backed up
                # as remote-mail accounts: if the zone has 1 mail. record,
                # and that record is a CNAME to the old Mail worker,
                # then prefer the template’s record instead of the
                # account archive’s.
                if ( $transfered_records_ref && @$transfered_records_ref == 1 ) {
                    my $cname = $transfered_records_ref->[0]{'cname'};

                    my $extractdir = $self->extractdir();
                    my $old_mx     = Whostmgr::Transfers::Utils::WorkerNodesObj->new($extractdir)->get_type_hostname('Mail');

                    return 0 if $old_mx && $old_mx eq $cname;
                }

                return _use_transferred_records_if_they_exist( $template_records_ref, $transfered_records_ref );
            },
        }
    );
}

# replace the NS lines from the newly created zone OVER the old zones NS lines if any exist. Otherwise, just add the new ones.
sub _merge_ns_records {
    my ( $self, $domain, $custom_zone_obj, $current_zone_obj ) = @_;

    return $self->_merge_records_of_types(
        {
            'custom_zone_obj'  => $custom_zone_obj,
            'current_zone_obj' => $current_zone_obj,
            'resource_types'   => ['NS'],
            'resource_names'   => [ $domain . '.' ],
        }
    );
}

sub _merge_soa_record {
    my ( $self, $custom_zone_obj, $current_zone_obj ) = @_;

    return $self->_merge_records_of_types(
        {
            'custom_zone_obj'  => $custom_zone_obj,
            'current_zone_obj' => $current_zone_obj,
            'resource_types'   => ['SOA']
        }
    );
}

####################################################################################
#
# Methods:
#   _merge_records_of_types
#
# Description:
#   This function merges records matching optional sets of record types and record names
#   in the $custom_zone_obj (transferred/restored) with the ones found in the $current_zone_obj
#   (created by DNS template locally). Any conflicting records will be commented out.
#
#   NOTE:  Please note that this function does NOT do CNAME conflict resolution. See
#          Cpanel::ZoneFile::Utils::comment_out_cname_conflicts for that functionality.
#
# Parameters:
#   $self             - this object
#   $opts             - hashref with the following parameters:
#   {
#      $custom_zone_obj   - The incoming transferred/restored zonefile as a Cpanel::ZoneFile obj.
#      $current_zone_obj  - The zonefile created by the DNS template system during account creation as a
#                           Cpanel::ZoneFile obj.
#      $resource_types_ar - An optional arrayref of DNS record types to merge
#      $resource_names_ar - An optional arrayref of DNS record names to merge, please note to make sure to
#                           specify the ending '.' if needed. Such as: somedomain.tld.
#      $filter_cr         - An optional coderef to further refine the objects that match the specified resource
#                           types and names
#
#      $prefer_transferred_records_cr - An optional coderef to determine if the incoming transferred/restored records
#                                       should be preferred over the template records. The coderef expects two array refs as parameters:
#                                          template_records_ref    => An arrayref of matching records from the zone template.
#                                          transferred_records_ref => An arrayref of matching records from the transferred/restored zone.
#   }
#
# Exceptions:
#   None currently.
#
# Returns;
#   Two-arg return.
#   $status - 0 for failure, 1 for success
#   $error  - error message
#
sub _merge_records_of_types {
    my ( $self, $opts ) = @_;

    my ( $custom_zone_obj, $current_zone_obj, $resource_types_ar, $resource_names_ar, $filter_cr, $prefer_transferred_records_cr ) = @{$opts}{qw( custom_zone_obj current_zone_obj resource_types resource_names filter prefer_transferred_records )};

    my @template_records = $current_zone_obj->find_records_with_names_types_filter(
        $resource_types_ar,
        $resource_names_ar,
        $filter_cr
    );

    my @transferred_records = $custom_zone_obj->find_records_with_names_types_filter(
        $resource_types_ar,
        $resource_names_ar,
        $filter_cr
    );

    # Remove equivalent records as to not replace/comment out a record if it isn't needed
    _remove_duplicate_records( \@template_records, \@transferred_records );

    if ( !$prefer_transferred_records_cr || !$prefer_transferred_records_cr->( \@template_records, \@transferred_records ) ) {

        # Lines start at 1
        my $line_to_insert_after = ( scalar @transferred_records ? $transferred_records[0]{'Line'} - 1 : $custom_zone_obj->get_line_number_after_soa_record() ) || 0;
        if ( $line_to_insert_after < 0 ) {
            return ( 0, $self->_locale()->maketext('The custom zone file is invalid.') );
        }

        # Should we comment them out even if there isn't a replacement in the template? I'm thinking no.
        $custom_zone_obj->comment_out_records( \@transferred_records, $MERGE_COMMENT ) if scalar @transferred_records && scalar @template_records;
        for my $new_record (@template_records) {
            $custom_zone_obj->insert_record_after_line( $new_record, $line_to_insert_after );
            $line_to_insert_after += ( $new_record->{'Lines'} || 1 );
        }
    }
    return 1;
}

####################################################################################
#
# Methods:
#   _remove_duplicate_records
#
# Description:
#   This function checks the records from two different arrayrefs of zone records and compares them.
#   It will remove any record equivalent with another record in the other arrayref from both arrayrefs.
#   We need to remove these records as to not comment out records that are equivalent.
#
# Parameters:
#   $self                   - this object
#   $template_records_ar    - An arrayref of zone records as defined by Cpanel::Net::DNS::ZoneFile::LDNS obtained from
#                             the templated zone file (created by create account in Whostmgr::Transfers::Systems::Account)
#                             and retrieved by Cpanel::ZoneFile::find_records_with_names_types_filter.
#                             NOTE: This may be modified by this method if equivalent records are found in $transferred_records_ar
#   $transferred_records_ar - An arrayref of zone records as defined by Cpanel::Net::DNS::ZoneFile::LDNS obtained from
#                             the transferred/restored zonefile (from the source machine or package)
#                             and retrieved by Cpanel::ZoneFile::find_records_with_names_types_filter.
#                             NOTE: This may be modified by this method if equivalent records are found in $template_records_ar
#
# Exceptions:
#   None currently.
#
# Returns;
#   Returns empty list. Instead it relies on modification of the passed in references.
#
sub _remove_duplicate_records {
    my ( $template_records_ar, $transferred_records_ar ) = @_;

    my $found_match;
    for my $transferred_records_index ( reverse 0 .. $#$transferred_records_ar ) {
        $found_match = 0;
        for my $template_records_index ( reverse 0 .. $#$template_records_ar ) {
            if (
                Cpanel::ZoneFile::Utils::are_records_equivalent(
                    $transferred_records_ar->[$transferred_records_index],
                    $template_records_ar->[$template_records_index]
                )
            ) {
                $found_match = 1;
                splice @$template_records_ar, $template_records_index, 1;
            }
        }
        splice @$transferred_records_ar, $transferred_records_index, 1 if $found_match;
    }

    return;
}

####################################################################################
#
# Methods:
#   _remove_old_automerge_comments
#
# Description:
#   This function will check the passed in zone object for old cPanel auto-merge comments as those added
#   by $custom_zone_obj->comment_out_cname_conflicts($MERGE_COMMENT); above. Any comments with a GMT timestamp
#   older than 30 days from the time of transfer/restore will be removed.
#
# Parameters:
#   $self                   - this object
#   $transferred_zone_obj   - A Cpanel::ZoneFile object representing the transferred/restored zonefile from the package.
#
# Exceptions:
#   None currently.
#
# Returns;
#   Returns empty list. Instead it relies on modification of the passed in object.
#
sub _remove_old_automerge_comments {
    my ($transferred_zone_obj) = @_;

    # Comments are represented by :RAW type records by Cpanel::Net::DNS::ZoneFile::LDNS, as are blank lines.
    my @raw_records           = $transferred_zone_obj->find_records_with_names_types_filter( [':RAW'] );
    my @old_automerge_records = grep { _raw_record_has_old_automerge_comment($_) } @raw_records;
    $transferred_zone_obj->remove_records( \@old_automerge_records ) if @old_automerge_records;

    return;
}

# Helper function for _remove_old_automerge_comments
# $record as defined by Cpanel::Net::DNS::ZoneFile::LDNS it should be a :RAW type record
# It will return 1 if the :RAW type record's text contains an auto-merge comment like
# the one found in $MERGE_COMMENT with a timestamp older than 30 days GMT from time of transfer/restore.
# It will return 0 if the $record isn't :RAW type or doesn't meet the above criteria.
sub _raw_record_has_old_automerge_comment {
    my ($record) = @_;

    return 0 if $record->{'type'} ne ':RAW';
    my $regex = get_merge_comment_regex();
    return 0 if $record->{'raw'} !~ $regex;
    my $gmt_timestamp = $1;

    my $comparison_timestamp = Cpanel::Time::time2condensedtime( time() - $MAX_COMMENT_AGE );
    return $comparison_timestamp > $gmt_timestamp;
}

sub _add_missing_subdomain_dns_entries {
    my ( $subs_ar, $ip ) = @_;

    return if !$subs_ar || @$subs_ar;

    my @install_list;
    my %base_domains_lookup;
    for (@$subs_ar) {
        m{\A([^.]+)[.](.*)\z};

        push @install_list,
          {
            match       => q{},
            removematch => q{},
            record      => $1,
            domain      => $2,
            value       => $ip,
          };

        $base_domains_lookup{$2} = undef;
    }

    #
    # Install each A record passed, with the '1' value to specify that records
    # of a matching name, type, and value, are not to be duplicated.  This does
    # not mangle round robin DNS records.
    #
    Cpanel::DnsUtils::Install::install_a_records( \@install_list, [ keys %base_domains_lookup ], 1 );

    return;
}

sub _get_related_ips {
    my ($self) = @_;

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    # This file is used to make better decisions about which
    # IPs should be treated as local IPs and which ones should be treated
    # as remote IPs for the purposes of restoring the account.
    #
    # We define related ips as ip addresses that exist in one of the
    # accounts dns zones and is local to the server the account
    # resided on at the time of packaging.
    #
    # The common complaint is that after the migration there are still ips
    # pointing at the old server. We find people adding dns entries to alias other
    # accounts and/or abuse the system to be able to use multiple shared ip by
    # changing the shared ip.
    #
    my $relatedips_file_path = "$extractdir/ips/related_ips";

    my $ips_str = Cpanel::LoadFile::load_if_exists($relatedips_file_path);

    return if !length $ips_str;

    my $wn_obj = Whostmgr::Transfers::Utils::WorkerNodesObj->new($extractdir);

    my @pre_validated_ips = (
        split( m{\n}, $ips_str ),
        $wn_obj->get_type_ipv4_addresses('Mail'),
        $wn_obj->get_type_ipv6_addresses('Mail'),
    );

    my %related_ips;

    foreach my $ip (@pre_validated_ips) {
        if ( Cpanel::Validate::IP::is_valid_ip($ip) ) {
            $related_ips{$ip} = 1;

            # The ip address may be in v6 or v4 format
            # so we need to handle both
            $related_ips{ Cpanel::IP::Convert::binip_to_human_readable_ip( Cpanel::IP::Convert::ip2bin16($ip) ) } = 1;
        }
        else {
            $self->{'_utils'}->warn( $self->_locale()->maketext( 'The system did not migrate the [output,abbr,DNS,Domain Name System] entries related to “[_1]” because it is not a valid IP address.', $ip ) );
        }
    }

    my @ips = sort keys %related_ips;

    return @ips;

}

sub _merge_records {
    my ( $self, $zone, $custom_zone_obj, $current_zone_obj ) = @_;
    my ( $ok, $error ) = $self->_merge_soa_record( $custom_zone_obj, $current_zone_obj );
    if ( !$ok ) {
        $self->{'_utils'}->warn( $self->_locale()->maketext( 'The system failed to update the [output,acronym,SOA,Start Of Authority] record for the domain “[_1]” because of an error: [_2]', $zone, $error ) );
    }

    ( $ok, $error ) = $self->_merge_ns_records( $zone, $custom_zone_obj, $current_zone_obj );
    if ( !$ok ) {
        $self->{'_utils'}->warn( $self->_locale()->maketext( 'The system failed to update the [output,acronym,NS,Name Server] record for the domain “[_1]” because of an error: [_2]', $zone, $error ) );
    }

    ( $ok, $error ) = $self->_merge_mail_records( $zone, $custom_zone_obj, $current_zone_obj );
    if ( !$ok ) {
        $self->{'_utils'}->warn( $self->_locale()->maketext( 'The system failed to update the [asis,mail] record for the domain “[_1]” because of an error: [_2]', $zone, $error ) );
    }

    ( $ok, $error ) = $self->_merge_ftp_records( $zone, $custom_zone_obj, $current_zone_obj );
    if ( !$ok ) {
        $self->{'_utils'}->warn( $self->_locale()->maketext( 'The system failed to update the [asis,ftp] record for the domain “[_1]” because of an error: [_2]', $zone, $error ) );
    }

    ( $ok, $error ) = $self->_merge_www_records( $zone, $custom_zone_obj, $current_zone_obj );
    if ( !$ok ) {
        $self->{'_utils'}->warn( $self->_locale()->maketext( 'The system failed to update the [asis,www] record for the domain “[_1]” because of an error: [_2]', $zone, $error ) );
    }

    ( $ok, $error ) = $self->_merge_main_domain_a_records( $zone, $custom_zone_obj, $current_zone_obj );
    if ( !$ok ) {
        $self->{'_utils'}->warn( $self->_locale()->maketext( 'The system failed to update the [asis,A] and [asis, AAAA] records for the domain “[_1]” because of an error: [_2]', $zone, $error ) );
    }

    ( $ok, $error ) = $self->_merge_mx_record_with_zero_preference( $zone, $custom_zone_obj, $current_zone_obj );
    if ( !$ok ) {
        $self->{'_utils'}->warn( $self->_locale()->maketext( 'The system failed to update the [output,acronym,MX,Mail Exchange] record for the domain “[_1]” because of an error: [_2]', $zone, $error ) );
    }
    return;
}

sub _load_zone_file_as_object {
    my ( $self, $zone, $zone_file_path ) = @_;
    my $err;
    my $zonedata;
    try {
        $zonedata = Cpanel::LoadFile::load( $zone_file_path, 0, $MAX_ZONEFILE_SIZE_BYTES + 1 );
    }
    catch {
        $err = $_;
    };

    if ( length $zonedata == $MAX_ZONEFILE_SIZE_BYTES + 1 ) {
        $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( "The system skipped restoring the zone “[_1]” because it exceeds the maximum size of [format_bytes,_2].", $zone, $MAX_ZONEFILE_SIZE_BYTES ) );
        return undef;

    }
    elsif ($err) {
        $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( "The system failed to load the file “[_1]” because of an error: [_2].", $zone_file_path, Cpanel::Exception::get_string($err) ) );
        return undef;
    }

    my ( $is_valid_zone, $error_or_zone ) = _validate_zone_data( $zone, $zonedata );
    if ( !$is_valid_zone ) {
        $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( 'The custom zone data for the domain “[_1]” is invalid. The error returned was: [_2]', $zone, $error_or_zone ) );
        return undef;
    }

    return $error_or_zone;
}

# Tested via t/integration/Whostmgr-Transfers-Systems-ZoneFile_can_restore_a_zonefile_with_has_no_userdata.t
#
sub _attach_zone_to_user {
    my ( $self, $zone, $username ) = @_;

    Cpanel::Config::ModCpUserFile::adddomaintouser( 'user' => $username, 'domain' => $zone, 'type' => '' );
    Cpanel::FileUtils::Lines::appendline( "/etc/userdomains", "$zone: $username" );
    return;
}

1;
