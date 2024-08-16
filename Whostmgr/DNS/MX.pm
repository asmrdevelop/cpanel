package Whostmgr::DNS::MX;

# cpanel - Whostmgr/DNS/MX.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::DNS::MX - Tools for managing MX entries

=head1 SYNOPSIS

    use Whostmgr::DNS::MX ();

    my %MXDATA = Whostmgr::DNS::MX::fetchmx($newdomain);

    my ( $detected, $unresolvable_ar ) = detect_mx_type_from_mxentries($MXDATA{'entries'});

=cut

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Config::CpUser::Object       ();
use Cpanel::Config::CpUserGuard          ();
use Cpanel::Config::IPs::RemoteMail      ();
use Cpanel::Config::LoadConfig           ();
use Cpanel::Config::LoadCpUserFile       ();
use Cpanel::ConfigFiles                  ();
use Cpanel::Debug                        ();
use Cpanel::DnsUtils::AskDnsAdmin        ();
use Cpanel::DnsUtils::Stream             ();
use Cpanel::Domain::Zone                 ();
use Cpanel::DomainIp                     ();
use Cpanel::Email::MX                    ();
use Cpanel::Ips::Fetch                   ();
use Cpanel::Ips::V6                      ();
use Cpanel::LinkedNode::Worker::Storage  ();
use Cpanel::MailTools::DBS               ();
use Cpanel::NAT                          ();
use Cpanel::Validate::IP::Expand         ();
use Cpanel::ZoneFile::Collection         ();
use Whostmgr::DNS::Constants             ();

our $NO_UPDATEUSERDOMAINS = 1;
our $DO_UPDATEUSERDOMAINS = 0;    # Default is 0 because its an inverse argument

our $NO_UPDATE_PROXY_SUBDOMAINS = 0;    # Default is not not update service (formerly proxy) subdomains
our $DO_UPDATE_PROXY_SUBDOMAINS = 1;

our $DO_MODIFY_MAIL_ROUTING = 0;        # modify mail routing by default
our $NO_MODIFY_MAIL_ROUTING = 1;

our $MX_ENTRY_IS_IMPUTED_FROM_A_RECORD = -1;

# checkmx:
#
# checkmx will ensure the localdomains,
# remotedomains, and secondarymx files are updated to
# reflect the mxcheck setting
#
# In the event mxcheck is set to auto:
# This function uses the data from a fetchmx* call to detect
# if the system should be configured as local/remote/secondary
# using the mx entries are configured in DNS and direct
# DNS lookups if needed.
#
# Note: there are many callers of this function that need
# the argument order preserved.  In v74 we plan on refactoring
# this to be a wrapper around a refectored version and adding POD
#
sub checkmx {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)
    my (
        $domain,                           # The domain to check the mx record for
        $mxentries,                        # The mx 'entries' value returned from fetchmx
        $alwaysaccept,                     # A legacy alwaysaccept value that will be passed though Cpanel::Email::MX::mx_compat
        $skip_updateuserdomains,           # $NO_UPDATEUSERDOMAINS or $DO_UPDATEUSERDOMAINS
        $update_proxy_subdomains,          # $NO_UPDATE_PROXY_SUBDOMAINS or $DO_UPDATE_PROXY_SUBDOMAINS
        $system_mail_routing_config_hr,    # OPTIONAL: The hashref from Cpanel::MailTools::DBS::fetch_system_mail_routing_config_by_domain()
        $cpuser_ref,                       # OPTIONAL: The cpanel users file hashref from Cpanel::Config::LoadCpUserFile
        $skip_modify_mail_routing          # OPTIONAL: If NO_MODIFY_MAIL_ROUTING /etc/localdomain,/etc/remotedomain, and /etc/secondarymx will not be modified
    ) = @_;

    $update_proxy_subdomains  ||= $NO_UPDATE_PROXY_SUBDOMAINS;
    $skip_modify_mail_routing ||= $DO_MODIFY_MAIL_ROUTING;
    $mxentries //= fetchmx_ref_nodetect($domain)->{'entries'};

    my $user =
        $cpuser_ref
      ? $cpuser_ref->{'USER'}
      : Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);

    my $configured_alwaysaccept = Cpanel::Email::MX::get_mxcheck_configuration( $domain, $user, $cpuser_ref );
    if ( defined $alwaysaccept ) {

        # 0 - auto, 1 - local
        $alwaysaccept = Cpanel::Email::MX::mx_compat($alwaysaccept);
    }
    else {
        $alwaysaccept = $configured_alwaysaccept;
    }

    if ( !$domain ) {
        return { 'mxcheck' => $alwaysaccept, 'changed' => 0, 'isprimary' => '', 'issecondary' => '', 'warnings' => ['No domain specified.'] };
    }
    if ( !$mxentries ) {
        return { 'mxcheck' => $alwaysaccept, 'changed' => 0, 'isprimary' => '', 'issecondary' => '', 'warnings' => "No MX entries found for $domain." };
    }

    #
    # Detection mechanisms, dragon in his den
    #
    my $warnings = '';
    my ( $detected, $detected_source ) = ( _get_mx_type_from_node_linkage( $cpuser_ref, $domain ), 'linkage' );
    if ( !$detected ) {
        ( $detected, $detected_source ) = ( _get_mx_type_from_alwaysaccept($alwaysaccept), 'alwaysaccept' );
    }
    if ( !$detected ) {
        my $unresolvable_ar;
        ( $detected, $unresolvable_ar, $detected_source ) = ( detect_mx_type_from_mxentries($mxentries), 'mxentries' );

        # Auto detect was not possible so load it from what is current
        if ( !$detected ) {
            ( $detected, $detected_source ) = ( _get_mx_type_from_disk( $domain, $system_mail_routing_config_hr ), 'disk' );

            # Default to local, not sure why this isn't auto like in Cpanel::Email::MX.
            if ( !$detected ) {
                $warnings .= "Failed to detect “$domain”’s MX type; defaulting to “local”.";
                ( $detected, $detected_source ) = ( 'local', 'default' );
            }

            elsif ( $unresolvable_ar && @$unresolvable_ar ) {
                $warnings .= "Auto Detect of MX configuration not possible due to non-resolving MX entries.  Defaulting to last known setting: $detected.\n";
                $warnings .= "The following entries could not be resolved: " . join( ',', @$unresolvable_ar ) . "\n";
            }

        }
    }

    #
    # Mutability: write to files, not sure why "checkmx" is doing this.
    #

    # NOTE we, don't use MXCHECK for linked-server-nodes, so skip it.
    if ( $alwaysaccept ne $configured_alwaysaccept and $detected_source ne 'linkage' ) {
        set_mxcheck_method( $domain, $alwaysaccept, $user );
    }

    # I don't understand why I can't qualify this with $detected_source ne 'disk'.
    # What's the point of detecting something
    if ( $detected && $detected_source ne 'disk' ) {
        my %opts = ( 'localdomains' => 0, 'remotedomains' => 0, 'secondarymx' => 0, 'update_proxy_subdomains' => $update_proxy_subdomains );
        if ( $detected eq 'local' ) {
            $opts{'localdomains'} = 1;
        }
        elsif ( $detected eq 'remote' ) {
            $opts{'remotedomains'} = 1;
        }
        elsif ( $detected eq 'secondary' ) {
            $opts{'remotedomains'} = 1;
            $opts{'secondarymx'}   = 1;
        }

        if ( $skip_modify_mail_routing == $DO_MODIFY_MAIL_ROUTING ) {
            Cpanel::MailTools::DBS::setup( $domain, %opts );
        }
    }

    if ( $skip_modify_mail_routing == $DO_MODIFY_MAIL_ROUTING ) {
        require Cpanel::SMTP::GetMX::Cache;
        Cpanel::SMTP::GetMX::Cache::delete_cache_for_domains( [$domain] );

        # Delay rebuilding the remote-MX cache by 60 seconds in order to
        # give the MX changes a bit of time to propagate …
        require Cpanel::ServerTasks;
        Cpanel::ServerTasks::schedule_task( ['EximTasks'], 60, "build_remote_mx_cache" );
    }

    return {
        'detected'    => $detected,
        'changed'     => ( $detected_source ne 'default' && $detected_source ne 'disk' ? 1 : 0 ),
        'mxcheck'     => $alwaysaccept,
        'local'       => ( $detected eq 'local'      ? 1 : 0 ),
        'remote'      => ( ( $detected eq 'remote' ) ? 1 : 0 ),
        'secondary'   => ( $detected eq 'secondary'  ? 1 : 0 ),
        'isprimary'   => ( $detected eq 'local'      ? 1 : 0 ),
        'issecondary' => ( $detected eq 'secondary'  ? 1 : 0 ),
        'warnings'    => [ split( /\n/, $warnings ) ],
    };
}

sub _get_mx_type_from_node_linkage ( $cpuser_ref, $domain ) {
    my $user = $Cpanel::user // Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);

    $cpuser_ref //= Cpanel::Config::LoadCpUserFile::load_if_exists($user);
    return undef unless $cpuser_ref;

    if ( ref $cpuser_ref eq 'HASH' ) { Cpanel::Config::CpUser::Object->adopt($cpuser_ref) }

    my $is_parent = Cpanel::LinkedNode::Worker::Storage::read( $cpuser_ref, 'Mail' );
    if ($is_parent) {
        return 'remote';
    }
    elsif ( grep { defined $_ && $_ eq 'Mail' } $cpuser_ref->child_workloads() ) {
        return 'local';
    }

    return undef;

}

# Alias to not break anything, we renamed sub
*_detect_mx_type = *_get_mx_type_from_disk;

sub _get_mx_type_from_disk ( $domain, $mail_route_cfg_hr ) {

    # Note: This will modify $mail_route_cfg_hr by loading the missing data
    # in the event that specific keys have not yet been loaded.  This is OK

    $mail_route_cfg_hr->{'local'} ||= Cpanel::Config::LoadConfig::loadConfig( $Cpanel::ConfigFiles::LOCALDOMAINS_FILE, undef, '' );
    if ( exists $mail_route_cfg_hr->{'local'}{$domain} ) {
        return 'local';
    }

    $mail_route_cfg_hr->{'remote'} ||= Cpanel::Config::LoadConfig::loadConfig( $Cpanel::ConfigFiles::REMOTEDOMAINS_FILE, undef, '' );

    if ( exists $mail_route_cfg_hr->{'remote'}{$domain} ) {
        $mail_route_cfg_hr->{'secondary'} ||= Cpanel::Config::LoadConfig::loadConfig( $Cpanel::ConfigFiles::SECONDARYMX_FILE, undef, '' );

        if ( exists $mail_route_cfg_hr->{'secondary'}{$domain} ) {
            return 'secondary';
        }

        return 'remote';
    }

    return undef;
}

sub _get_mx_type_from_alwaysaccept ($alwaysaccept) {
    if ( $alwaysaccept eq 'local' ) {
        return 'local';
    }
    elsif ( $alwaysaccept eq 'secondary' || $alwaysaccept eq 'backup' ) {
        return 'secondary';
    }
    elsif ( $alwaysaccept eq 'remote' ) {
        return 'remote';
    }
    return undef;
}

=head2 detect_mx_type_from_mxentries($mxentries_ar)

Auto detect how the domain should be treated
for exchanging mail on this machine.

=over 2

=item Input

=over 3

=item $mxentries C<ARRAYREF>

This function takes the mx entries in the format
returned by fetchmx*’s entries field.

=back

=item Output

=over 3

=item $detected C<SCALAR>

    One of the following values:
    'local' - The mail is handled locally
    'remote' - The mail is handled remotely
    'secondary' - The mail is queued locally and delivered to remote
    undef - The system could not auto detect from the mx entries

=item $unresovable_ar C<ARRAYREF>

    If $detected is undef, $unresovable_ar will
    be an arrayref of the domains that could
    not be resolved which prevented the
    auto detection.

=back

=back

=cut

sub detect_mx_type_from_mxentries {
    my ($mxentries_ar) = @_;

    my $mailips_hr = _get_mailips();
    my ( $lowest_priority, $is_primary_mx, $is_secondary_mx, $unresovable_ar, $detected, $apache_conf_cache );
    my $auto_detect_possible = 1;

  MXENTRIES:
    foreach my $entry ( sort { $a->{'priority'} <=> $b->{'priority'} } @{$mxentries_ar} ) {    #important we check in order or we will get it wrong
        next if !$entry;

        my ( $this_mx_entry_ip_address, $this_mx_entry_is_local_ip );

        $lowest_priority //= $entry->{'priority'};

        if ( $entry->{'ipdb'} && exists $entry->{'ipdb'}->{ $entry->{'mxentry'} } ) {
            $this_mx_entry_ip_address = Cpanel::NAT::get_local_ip( $entry->{'ipdb'}->{ $entry->{'mxentry'} } );
        }
        else {
            require Cpanel::SocketIP;
            $this_mx_entry_ip_address = Cpanel::NAT::get_local_ip( Cpanel::SocketIP::_resolveIpAddress( $entry->{'mxentry'}, 'timeout' => 10 ) );
            if ( !$this_mx_entry_ip_address ) {
                $this_mx_entry_ip_address = Cpanel::DomainIp::getdomainip( $entry->{'mxentry'} );
                if ($this_mx_entry_ip_address) {
                    Cpanel::Debug::log_info("[checkmx] $entry->{'mxentry'} could not be resolved using dns; using domain owner’s IP address ($this_mx_entry_ip_address)");
                }
            }
            else {
                Cpanel::Debug::log_info("[checkmx] $entry->{'mxentry'} was resolved using gethostbyname to $this_mx_entry_ip_address");
            }
        }

        if ( !$this_mx_entry_ip_address ) {
            push @$unresovable_ar, $entry->{'mxentry'};
            Cpanel::Debug::log_info("[checkmx] $entry->{'mxentry'} could not be resolved or read from the user config (using last setting instead of auto detect)");
            $auto_detect_possible = 0;
            last MXENTRIES;
        }
        elsif ( $mailips_hr->{$this_mx_entry_ip_address} ) {
            $this_mx_entry_is_local_ip = 1;
        }

        if ( $entry->{'priority'} == $lowest_priority && $this_mx_entry_is_local_ip ) {
            $is_primary_mx = 1;
        }
        elsif ( $entry->{'priority'} > $lowest_priority && $this_mx_entry_is_local_ip ) {
            $is_secondary_mx = 1;
        }
    }

    if ($auto_detect_possible) {
        if ($is_primary_mx) {
            $detected = 'local';
        }
        elsif ($is_secondary_mx) {
            $detected = 'secondary';
        }
        else {
            $detected = 'remote';
        }
    }

    return ( $detected, $unresovable_ar );
}

# fetchmx:
# Fetch MX entreies for a given domain, and detect if the mx
# type is local, remove, or secondary
#
# Avoid this legacy function in new code as it
# ** RETURNS A COPY OF A HASH **
#
# Note: there are many callers of fetchmx* functions that need
# the argument order preserved.  In v74 we plan on refactoring
# this to be a wrapper around a refectored version and adding POD
#
# Additionally a copy of the raw zone file is returning
# in the zone key.
#
sub fetchmx {
    return %{ _fetchmx_backend( { 'detect' => 1, 'return_zone' => 1 }, @_ ) };
}

# fetchmx_ref_nodetect:
# Fetch MX entries for a given domain, but skips the detection of the mx
# type being local, remove, or secondary
#
# Unlike fetchmx a copy of the zonefile is not returned in the zone key
sub fetchmx_ref_nodetect {
    return _fetchmx_backend( { 'detect' => 0 }, @_ );
}

# fetchmx_ref_detect:
# Fetch MX entreies for a given domain, and detect if the mx
# type is local, remove, or secondary
#
# Unlike fetchmx a copy of the zonefile is not returned in the zone key
sub fetchmx_ref_detect {
    return _fetchmx_backend( { 'detect' => 1 }, @_ );
}

# TODO in v74+, Refactor, POD
sub _fetchmx_backend {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)
    my (
        $opts,
        $domain,                           # The domain to fetch the mx record for
        $rZONEMAP,                         # OPTIONAL: A zone map as fetched by Cpanel::Domain::Zone->new()->get_zones_for_domains via Cpanel::DnsUtils::Fetch
        $system_mail_routing_config_hr,    # OPTIONAL: The hashref from Cpanel::MailTools::DBS::fetch_system_mail_routing_config_by_domain()
        $cpuser_ref,                       # OPTIONAL: The cpanel users file hashref from Cpanel::Config::LoadCpUserFile
        $zone_file_objs_hr,                # OPTIONAL: A hashref of Cpanel::ZoneFile objects per for each zone
        $zone_file_ipdbs_hr,               # OPTIONAL: A hashref of generate_ipdb_from_zonefile_obj() for each zone
        $possible_zones_for_domain_ar      # OPTIONAL: An arrayref of possible zones for the domain
    ) = @_;

    $domain =~ s/\.db$//;
    my $domain_zone_obj;

    # Fill in data that was not passed
    unless ( ref $rZONEMAP eq 'HASH' ) {
        $rZONEMAP = ( ( $domain_zone_obj ||= Cpanel::Domain::Zone->new() )->get_zones_for_domains( [$domain] ) )[1];
    }
    $possible_zones_for_domain_ar ||= [ ( $domain_zone_obj ||= Cpanel::Domain::Zone->new() )->get_possible_zones_for_domain($domain) ];
    $zone_file_objs_hr            ||= Cpanel::ZoneFile::Collection::create_zone_file_objs($rZONEMAP);
    $zone_file_ipdbs_hr           ||= create_ipdbs_for_zonefile_objs($zone_file_objs_hr);

    my %MX;
    my %IPDB_WANT = ( $domain => 1 );
    my %IPDB;
    my $hasmx = 0;
  POSSIBLE_ZONE:
    foreach my $possible_zonefile (@$possible_zones_for_domain_ar) {
        my $zonefile_obj             = $zone_file_objs_hr->{$possible_zonefile} or next;
        my $domain_with_trailing_dot = "$domain.";

        # Ensure that we're looking at the right MX entry
        foreach my $record ( grep { $_->{'name'} eq $domain_with_trailing_dot } @{ $zonefile_obj->find_records_cached( { 'type' => 'MX' } ) } ) {
            my $name     = substr( $record->{'name'}, 0, -1 );
            my $mxserver = $zonefile_obj->_domain( $record->{'exchange'} );
            chop($mxserver);
            if ( index( $mxserver, 'mx-' ) == 0 && $mxserver =~ m/^mx-(\d+)-(\d+)-(\d+)-(\d+)/ ) {
                $mxserver = $1 . '.' . $2 . '.' . $3 . '.' . $4;
            }
            $IPDB_WANT{$mxserver} = 1;
            push(
                @{ $MX{$domain} },
                {
                    'priority'  => $record->{'preference'},
                    'zonefile'  => $possible_zonefile,
                    'server'    => $mxserver,
                    'linecount' => ( $record->{'Line'} - 1 ),
                    'premx'     => join( "\t", ( $zonefile_obj->_build_basic_record($record) )[ 0 .. 2 ] )
                }
            );
            $hasmx = 1;
        }
    }

    # Only load items into the ipdb we care about which includes
    # the domain and all the exchangers
    my $ip;
    foreach my $possible_zonefile (@$possible_zones_for_domain_ar) {
        my $zone_ipdb = $zone_file_ipdbs_hr->{$possible_zonefile};
        foreach my $name ( keys %IPDB_WANT ) {
            if ( $ip = $zone_ipdb->{$name} ) {
                $IPDB{$name} = $ip;
            }
        }
    }

    my $zonefile;
    my $entrycount = 0;
    my @RET;
    foreach my $server ( keys %MX ) {    # sort by order
        foreach my $mx ( sort { $a->{'priority'} <=> $b->{'priority'} } @{ $MX{$server} } ) {
            $zonefile ||= $mx->{'zonefile'};
            push @RET,
              {
                'entrycount' => ++$entrycount,
                'server'     => $server,
                'type'       => 'MX',
                'priority'   => $mx->{'priority'},
                'ipdb'       => \%IPDB,
                'mxentry'    => $mx->{'server'},
                'premx'      => $mx->{'premx'},
                'linenum'    => $mx->{'linecount'},
                'zonefile'   => $mx->{'zonefile'}
              };
        }
    }
    if ( !@RET ) {
        if ( !$zonefile ) {

            # If there is no entry the first one in the possible_zones_for_domain_ar
            # that has a zone file is the one we want
            foreach my $possible_zonefile (@$possible_zones_for_domain_ar) {
                my $zonefile_obj = $zone_file_objs_hr->{$possible_zonefile} or next;
                $zonefile = $possible_zonefile;
                last;
            }
        }
        my $entry = {
            'entrycount' => 1,
            'server'     => $domain,
            'type'       => 'A',
            'priority'   => 0,
            'ipdb'       => \%IPDB,
            'mxentry'    => $domain,
            'premx'      => $domain,
            'linenum'    => $MX_ENTRY_IS_IMPUTED_FROM_A_RECORD,
            'zonefile'   => ( $zonefile || $domain )
        };

        if ( exists $IPDB{$domain} ) {
            push @RET, $entry;
        }
        else {
            $entry->{'type'} = 'UNKNOWN';
            push @RET, $entry;
        }
    }

    my $user    = $cpuser_ref ? $cpuser_ref->{'USER'} : Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);
    my $mxcheck = Cpanel::Email::MX::get_mxcheck_configuration( $domain, $user, $cpuser_ref );

    my %detected_values;
    if ( $opts->{'detect'} ) {
        %detected_values = ( 'local' => 0, 'remote' => 0, 'secondary' => 0 );
        my $current_detected_setting;
        if ( $mxcheck eq 'auto' ) {
            ($current_detected_setting) = detect_mx_type_from_mxentries( \@RET );
        }
        else {
            $current_detected_setting = $mxcheck;
        }
        $current_detected_setting ||= _get_mx_type_from_disk( $domain, $system_mail_routing_config_hr );
        if ($current_detected_setting) {
            $detected_values{$current_detected_setting} = 1;
        }
        $detected_values{'detected'} = $current_detected_setting || 'auto';
    }

    my $zone_ar;
    if ( $opts->{'return_zone'} ) {
        if ($zonefile) {
            $zone_ar = ref $rZONEMAP->{$zonefile} ? $rZONEMAP->{$zonefile} : [ split( m{\n}, $rZONEMAP->{$zonefile} ) ];
        }
    }
    return {
        'entries' => \@RET,
        ( $opts->{'return_zone'} ? ( 'zone' => ( $zonefile ? $zone_ar : undef ) ) : () ),
        'domain'       => $domain,
        'mxcheck'      => $mxcheck,
        'alwaysaccept' => ( $mxcheck eq 'local' ? 1 : 0 ),
        'zonefile'     => $zonefile,
        %detected_values,    # only filled if detect is enabled
    };
}

sub delmx {
    my ( $priority, $zone, $skip_checkmx, $requested_mxentry ) = @_;

    my $domain = $zone;
    $domain =~ s/\.db$//;

    my %MXDATA = fetchmx($zone);

    my $zonefile = $MXDATA{'zonefile'};

    my @ZFILE     = @{ $MXDATA{'zone'} };
    my @MXENTRIES = @{ $MXDATA{'entries'} };
    my ($entryline);
    my $entrynum = 0;
    my $mxentry;
    foreach my $entry (@MXENTRIES) {
        if ( $entry->{'priority'} eq $priority ) {
            if ( $requested_mxentry && $entry->{'mxentry'} ne $requested_mxentry ) { next; }

            # only delete a MX record
            next if !$entry->{'type'} || $entry->{'type'} ne 'MX';
            $entryline = $entry->{'linenum'};
            $mxentry   = $entry->{'mxentry'};
            last;
        }
        $entrynum++;
    }

    my @REMOVED_MXENTRIES = map { "$_->{'premx'} $_->{'type'} $_->{'priority'} $_->{'mxentry'}" } grep { $_->{'linenum'} == $entryline } @MXENTRIES;

    if ($entryline) {
        @MXENTRIES = grep { $_->{'linenum'} != $entryline } @MXENTRIES;
    }
    if ( $#ZFILE == -1 ) {
        return ( 0, "Error fetching zone data for ${zone}'s MX" );
    }
    if ($entryline) {
        splice( @ZFILE, $entryline, 1 );
    }
    else {
        return ( 0, "No MX entries with priority $priority were found in the zone." );
    }

    if ( $mxentry =~ /^\d+\.\d+\.\d+\.\d+$/ ) {
        $mxentry = 'mx-' . $mxentry;
        $mxentry =~ s/\./\-/g;

        my @NZFILE;
        my $modded = 0;
        foreach (@ZFILE) {
            if ( !m/^\s*\Q$mxentry\E\s+/ ) {
                push @NZFILE, $_;
                $modded = 1;
            }
        }
        if ($modded) {
            @ZFILE = @NZFILE;
        }
        undef @NZFILE;
    }

    my $zret = '';

    foreach my $entry (@REMOVED_MXENTRIES) {
        $zret .= "Removed entry: $entry\n";
    }

    my $zonedata = join( "\n", @ZFILE );
    $zonedata = Cpanel::DnsUtils::Stream::upsrnumstream($zonedata);
    $zret .= Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "SAVEZONE", 0, $zonefile, $zonedata );
    $zret .= Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "RELOADBIND", 0, $zonefile );

    if ($skip_checkmx) { return ( 1, 'ok', [] ); }

    my $cmx = checkmx( $domain, \@MXENTRIES );
    return ( 1, $zret, $cmx );
}

sub savemx {
    my ( $mx, $priority, $zone, $mxcheck, $skip_checkmx, $keepsamepriority, $oldmx, $oldpriority ) = @_;

    $mx =~ s/\.$//g;
    my $domain = $zone;
    $domain =~ s/\.db$//g;

    my %MXDATA    = fetchmx($zone);
    my $zonefile  = $MXDATA{'zonefile'};
    my @ZFILE     = @{ $MXDATA{'zone'} };
    my @MXENTRIES = @{ $MXDATA{'entries'} };
    my ( $type, $data, $predata, $entryline );

    # keepsameprio  = ADD ACTION
    # MX entry should only match if
    # priority = priority
    # mx = mx
    # !keepsameprio = CHANGE ACTION
    # MX entry should only match if
    #
    my $already_done = 0;

    my $zret = '';

    #
    # First change we look to see if what we are about to put in is already there and reuse the line
    #
    my $entrynum = 0;
    foreach my $entry (@MXENTRIES) {
        next if $entry->{'type'} ne 'MX';    #handle a fallback records
        if ( $mx eq $entry->{'mxentry'} && $entry->{'priority'} eq $priority ) {
            ( $type, $data, $predata, $entryline, $zonefile ) = ( $entry->{'type'}, $entry->{'mxentry'}, $entry->{'premx'}, $entry->{'linenum'}, ( $entry->{'zonefile'} ? $entry->{'zonefile'} : $zonefile ) );
            $zret .= "Reusing existing entry on line matched new entry and new priority: " . ( $entryline + 1 ) . ":\n";
            $already_done = 1;
            last;
        }
        $entrynum++;
    }

    #
    # If we specify the old mx and old priority to replace then use these
    #
    if ( !$entryline && defined $oldpriority && $oldmx ) {
        $entrynum = 0;
        foreach my $entry (@MXENTRIES) {
            next if ( $entry->{'linenum'} == -1 );    #handle a fallback records
            if ( $oldmx eq $entry->{'mxentry'} && $oldpriority eq $entry->{'priority'} ) {
                ( $type, $data, $predata, $entryline, $zonefile ) = ( $entry->{'type'}, $entry->{'mxentry'}, $entry->{'premx'}, $entry->{'linenum'}, ( $entry->{'zonefile'} ? $entry->{'zonefile'} : $zonefile ) );
                $zret .= "Replacing existing entry on line matched old entry and old priority: " . ( $entryline + 1 ) . ":\n";
                last;
            }
            $entrynum++;
        }

        #
        # If we specify the old mx but not old priority then replace the oldmx + the new priority if it exists
        #
    }
    elsif ( !$entryline && $oldmx ) {
        $entrynum = 0;
        foreach my $entry (@MXENTRIES) {
            next if ( $entry->{'linenum'} == -1 );    #handle a fallback records
            if ( $oldmx eq $entry->{'mxentry'} && $priority eq $entry->{'priority'} ) {
                ( $type, $data, $predata, $entryline, $zonefile ) = ( $entry->{'type'}, $entry->{'mxentry'}, $entry->{'premx'}, $entry->{'linenum'}, ( $entry->{'zonefile'} ? $entry->{'zonefile'} : $zonefile ) );
                $zret .= "Replacing existing entry on line matched old entry and existing priority: " . ( $entryline + 1 ) . ":\n";
                last;
            }
            $entrynum++;
        }
    }

    #
    # Legacy behavior -- match only on priority
    #
    if ( !$entryline && !$keepsamepriority ) {
        $entrynum = 0;
        foreach my $entry (@MXENTRIES) {
            next if ( $entry->{'linenum'} == -1 );    #handle a fallback records
            if ( $entry->{'priority'} eq $priority ) {
                ( $type, $data, $predata, $entryline, $zonefile ) = ( $entry->{'type'}, $entry->{'mxentry'}, $entry->{'premx'}, $entry->{'linenum'}, ( $entry->{'zonefile'} ? $entry->{'zonefile'} : $zonefile ) );
                $zret .= "Replacing existing entry on line matched old priority: " . ( $entryline + 1 ) . ":\n";
                last;
            }
            $entrynum++;
        }
    }

    if ( !$already_done ) {
        if ( !$entryline ) {
            $entryline = $#ZFILE + 1;
        }

        if ( $#ZFILE == -1 ) {
            return ( 0, "Error fetching zone data for ${zone}'s MX" );
        }
        my $mxipname;
        if ( $mx =~ /^\d+\.\d+\.\d+\.\d+$/ ) {
            $mxipname = 'mx-' . $mx;
            $mxipname =~ s/\./\-/g;
        }
        if ( defined $type && $type eq 'MX' ) {    #entry already exists
            if ($mxipname) {
                splice( @ZFILE, $entryline, 1, "$mxipname IN A $mx", "$predata MX $priority $mxipname" );
            }
            else {
                splice( @ZFILE, $entryline, 1, "$predata MX $priority ${mx}." );
            }
            $MXENTRIES[$entrynum]->{'mxentry'}  = $mx;
            $MXENTRIES[$entrynum]->{'priority'} = $priority;

            my %remove_dupes_saw;
            @ZFILE = grep( ( /^\s*mx\-\d+\-\d+\-\d+\-\d+\s*/ && /\s*A\s*/ ) ? !$remove_dupes_saw{$_}++ : 1, @ZFILE );
        }
        else {

            my $frontline = $domain;

            # do not strip the zone name off
            #$frontline =~ s/\.${zonefile}$//g;

            if ($mxipname) {
                push @ZFILE, "$mxipname IN A $mx\n$frontline. IN MX $priority $mxipname\n";
                $zret .= "Added entry and A Record: $ZFILE[-1]\n";
            }
            else {
                push @ZFILE, "$frontline.    IN    MX    $priority    ${mx}.\n";
                $zret .= "Added entry: $ZFILE[-1]\n";
            }

            my %remove_dupes_saw;
            @ZFILE = grep( ( /^\s*mx\-\d+\-\d+\-\d+\-\d+\s*/ && /\s*A\s*/ ) ? !$remove_dupes_saw{$_}++ : 1, @ZFILE );

            push @MXENTRIES,
              {
                server     => $frontline,
                type       => 'MX',
                priority   => $priority,
                mxentry    => $mx,
                'zonefile' => $zonefile,
                premx      => "$frontline IN",
                linenum    => $#ZFILE
              };
        }

        my $zonedata = join( "\n", @ZFILE );
        $zonedata = Cpanel::DnsUtils::Stream::upsrnumstream($zonedata);
        $zret .= Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "SAVEZONE", 0, $zonefile, $zonedata );
        $zret .= Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "RELOADBIND", 0, $zonefile );
    }
    else {
        $zret .= "No dns changes are required";
    }

    @MXENTRIES = grep { $_->{'linenum'} != -1 } @MXENTRIES;    #case 33170 :: remove any fallback A entries now
                                                               # that we have an entry in the zone

    if ($skip_checkmx) {
        set_mxcheck_method( $domain, $mxcheck ) if ( defined $mxcheck );
        return ( 1, 'ok', [] );
    }
    else {
        my $cmx = checkmx( $domain, \@MXENTRIES, $mxcheck );
        return ( 1, $zret, $cmx );
    }
}

sub set_always_accept {
    goto &set_mxcheck_method;
}

sub set_mxcheck_method {
    my ( $domain, $alwaysaccept, $user ) = @_;
    $user //= Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);
    return if ( !defined $user || $user eq 'root' );

    # MXCHECK is ignored in CpUser files on nodes that are parent or child.
    # They should not call this method.
    if ( my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load_if_exists($user) ) {
        require Cpanel::LinkedNode::Worker::Storage;

        # If called from a parent
        if ( Cpanel::LinkedNode::Worker::Storage::read( $cpuser_ref, 'Mail' ) ) {
            die "You cannot call mxcheck if there is a child node";
        }

        # If called from a child
        elsif ( grep { defined $_ && $_ eq 'Mail' } $cpuser_ref->child_workloads() ) {
            die "You cannot call mxcheck if there is a parent node";
        }
    }
    else {

        # The user does not exist
        return;
    }

    $alwaysaccept //= 0;
    $alwaysaccept = 'secondary' if $alwaysaccept eq 'backup';

    my $method = Cpanel::Email::MX::mx_compat($alwaysaccept);
    return unless $method && grep { $_ eq $method } @Whostmgr::DNS::Constants::MXCHECK_OPTIONS;

    # No sense getting the user guard object till we're sure we aren't just needing to return undef above
    my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
    if ( $method eq 'local' ) {
        if ( ( $cpuser_guard->{'data'}->{ 'MXCHECK-' . $domain } || '' ) ne '0' ) {
            $cpuser_guard->{'data'}->{ 'MXCHECK-' . $domain } = '0';
            $cpuser_guard->save();
        }
    }
    elsif ( $method eq 'auto' ) {
        if ( exists $cpuser_guard->{'data'}->{ 'MXCHECK-' . $domain } ) {
            delete $cpuser_guard->{'data'}->{ 'MXCHECK-' . $domain };
            $cpuser_guard->save();
        }
    }
    elsif ( ( $cpuser_guard->{'data'}->{ 'MXCHECK-' . $domain } || q<> ) ne $method ) {
        $cpuser_guard->{'data'}->{ 'MXCHECK-' . $domain } = $method;
        $cpuser_guard->save();
    }
    return { 'mxcheck' => $method, 'alwaysaccept' => $alwaysaccept };
}

sub does_alwaysaccept {
    goto &Cpanel::Email::MX::does_alwaysaccept;
}

my $_get_mailips;

sub _get_mailips {
    return $_get_mailips ||= do {

        my %IPS = (
            Cpanel::Ips::Fetch::fetchipslist(),
            map { $_ => 1 } (
                Cpanel::Ips::V6::fetchipv6list(),
                @{ Cpanel::Config::IPs::RemoteMail->read() },
            ),
        );

        \%IPS;
    };
}

sub generate_ipdb_from_zonefile_obj {
    my ($zonefile_obj) = @_;
    my ( %CNAMEDB, %IPv4DB, %IPv6DB );
    foreach my $record ( @{ $zonefile_obj->{'dnszone'} } ) {
        if ( $record->{'type'} eq 'CNAME' ) {
            $CNAMEDB{ substr( $record->{'name'}, 0, -1 ) } = $record->{'cname'};
        }
        elsif ( $record->{'type'} eq 'A' ) {
            $IPv4DB{ substr( $record->{'name'}, 0, -1 ) } = $record->{'address'};
        }
        elsif ( $record->{'type'} eq 'AAAA' ) {
            $IPv6DB{ substr( $record->{'name'}, 0, -1 ) } = Cpanel::Validate::IP::Expand::normalize_ipv6( $record->{'address'} );
        }
    }

    # Prefer IPv4 over IPv6 when we have an AAAA and an A entry.
    # We currently do not migrate IPv6 addresses on transfer so it very
    # important that we use the IPv4 address to determine if the
    # MX is local or remote.
    my %IPDB = ( %IPv6DB, %IPv4DB );

    foreach my $name ( keys %CNAMEDB ) {
        if ( exists $IPDB{ $CNAMEDB{$name} } && !exists $IPDB{$name} ) {
            $IPDB{$name} = $IPDB{ $CNAMEDB{$name} };
        }
    }

    return \%IPDB;
}

sub create_ipdbs_for_zonefile_objs {
    my ($zone_file_objs_hr) = @_;
    return { map { $_ => generate_ipdb_from_zonefile_obj( $zone_file_objs_hr->{$_} ) } keys %$zone_file_objs_hr };
}

1;
