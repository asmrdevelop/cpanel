package Cpanel::ZoneFile;

# cpanel - Cpanel/ZoneFile.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DnsUtils::RR             ();
use Cpanel::Hostname                 ();
use Cpanel::Debug                    ();
use Cpanel::Version::Full            ();
use Cpanel::Net::DNS::ZoneFile::LDNS ();
use Cpanel::Time                     ();
use Cpanel::ZoneFile::Versioning     ();

our $VERSION = $Cpanel::ZoneFile::Versioning::VERSION;
our $DEBUG   = 0;

# The keys that should be in a :RAW record according to Cpanel::Net::DNS::ZoneFile::LDNS
# Note: Comments are parsed as :RAW records.
my %COMMENT_KEY_LOOKUP = map { $_ => 1 } qw( type ttl raw Line );

# The default number of lines in an SOA record. This is set per conventional format:
# example.com.    IN    SOA   ns.example.com. hostmaster.example.com. (
#                               2003080800 ; sn = serial number
#                               172800     ; ref = refresh = 2d
#                               900        ; ret = update retry = 15m
#                               1209600    ; ex = expiry = 2w
#                               3600       ; nx = nxdomain ttl = 1h
#                               )
# cf. http://www.zytrax.com/books/dns/ch8/soa.html
my $DEFAULT_SOA_LINES_PER_CONVENTION = 7;

our $FALLBACK_TTL = 14400;

# args:
#   - pretty_print
#   - domain
#   - text
#   - hostname
#   - update_time
#
sub new {
    my ( $class, %opts ) = @_;

    my $self = bless {
        'modified' => 0,
    }, $class;
    $self->{'pretty_print'} = $opts{'pretty_print'};
    if ( !$opts{'domain'} ) {
        $self->{'status'} = 0;
        $self->{'error'}  = 'No domain specified';
        Cpanel::Debug::log_die('No domain specified');
    }
    elsif ( !$opts{'text'} ) {
        $self->{'status'} = 0;
        $self->{'error'}  = "No zonefile data provided for “$opts{'domain'}”.";
        Cpanel::Debug::log_warn( $self->{'error'} );
        return $self;
    }
    $self->{'zoneroot'} = lc $opts{'domain'};
    $self->{'zoneroot'} =~ s/^\.|\.$//g;
    $self->{'zoneroot_trailer'}        = '.' . $self->{'zoneroot'} . '.';
    $self->{'zoneroot_trailer_length'} = length( $self->{'zoneroot_trailer'} );
    $self->{'status'}                  = 1;
    $self->{'hostname'}                = $opts{'hostname'};
    $self->{'update_time'}             = $opts{'update_time'};
    local $@;
    eval {
        $self->{'dnszone'} = Cpanel::Net::DNS::ZoneFile::LDNS::parse( 'text' => $opts{'text'}, 'origin' => $self->{'zoneroot'} . '.', 'tolower' => 1, 'quiet' => 1 );

        Cpanel::DnsUtils::RR::cp_zonefile_fast_post_process( $self->{'dnszone'} );

        ( $self->{'defaultttl'} ) = ( ( map { $_->{'ttl'} } grep { $_->{'type'} eq '$TTL' } @{ $self->{'dnszone'} } ), $FALLBACK_TTL );
    };

    if ($@) {
        my $err = $@;
        $self->{'parse_error'} = $err;
        $self->{'status'}      = 0;
        Cpanel::Debug::log_warn("Error while parsing zonedata for $opts{'domain'}: $err");
        my $clean_error = ( split( /\.\.\./, $err ) )[0];
        $clean_error =~ s{\s+$}{}g;

        my ($linenum) = $clean_error =~ m{line\s+(\d+)};
        my $raw_record = '';
        if ($linenum) {
            my @rawtext = ref $opts{'text'} ? ( split( m{\n}, join( "\n", @{ $opts{'text'} } ) ) ) : split( m{\n}, $opts{'text'} );
            $raw_record = $rawtext[ $linenum - 1 ];
        }

        $self->{'error'} = "There was an error while loading the zone for $opts{'domain'}.  Please correct any errors in this zone manually and try again.  The exact error from the parser was: $clean_error: [$raw_record]";
    }
    elsif ( !$self->{'dnszone'} ) {
        $self->{'status'} = 0;
        $self->{'error'}  = 'Undetermined error. No zone data.';
        Cpanel::Debug::log_warn('Undetermined error. No zone data.');
    }
    $self->{'method'} = 'text';
    return $self;
}

sub serialize_for_display {
    my $self = shift;
    return $self->build_zone_for_display();
}

sub serialize {
    my $self = shift;
    return $self->build_zone();
}

sub add_record {
    my ( $self, $record ) = @_;

    $self->{'modified'} = 1;
    push @{ $self->{'dnszone'} }, {
        %$record,
        Line => ( 1 + ( scalar @{ $self->{'dnszone'} } ? $self->{'dnszone'}[-1]{'Line'} : 1 ) ),
    };

    return 1;
}

sub get_serial_number {
    my ($self) = @_;

    my $soa = $self->get_soa_record();
    return $soa->{'serial'};
}

sub get_line_number_after_soa_record {
    my ($self) = @_;

    my $soa = $self->get_soa_record();
    return if !$soa;
    return $soa->{'Line'} + ( $soa->{'Lines'} || $DEFAULT_SOA_LINES_PER_CONVENTION );
}

sub get_soa_record {
    my ($self) = @_;

    my @records = $self->find_records( { 'type' => 'SOA' } );
    return if !scalar @records;

    my ($soa) = @records;
    return $soa;
}

sub find_records {
    my $self = shift;
    my ( $name, $type, $cache_key ) = $self->_parse_find_records_opts( ref $_[0] ? $_[0] : {@_} );
    my ($record_ref) = $self->_find_records( $name, $type );
    return wantarray ? @$record_ref : $record_ref;
}

sub find_records_cached {
    my $self = shift;
    my ( $name, $type, $cache_key ) = $self->_parse_find_records_opts( ref $_[0] ? $_[0] : {@_} );
    if ( $self->{'modified'} ) {

        # If the zone has been modified delete the cache
        delete $self->{'_find_records_cache'};
        return $self->_find_records( $name, $type );
    }
    elsif ( $self->{'_find_records_cache'}{$cache_key} ) {
        return $self->{'_find_records_cache'}{$cache_key};
    }
    return ( $self->{'_find_records_cache'}{$cache_key} = $self->_find_records( $name, $type ) );
}

sub _parse_find_records_opts {
    my ( $self, $opt_ref ) = @_;
    my $name = $opt_ref->{'name'} || 0;
    my $type = $opt_ref->{'type'} || 0;
    if ( $name && substr( $name, -1, 1 ) ne '.' ) {
        $name .= $self->{'zoneroot_trailer'};
    }
    return ( $name, $type, "${name}__${type}" );
}

sub _find_records {
    my ( $self, $name, $type ) = @_;
    return [ grep { ( !$type || $_->{'type'} eq $type ) && ( !$name || ( $_->{'name'} && $_->{'name'} eq $name ) ) } @{ $self->{'dnszone'} } ];
}

sub replace_records {
    my $self          = shift;
    my $newrecordsref = shift;

    $self->{'modified'} = 1;
    my %NEWRECORDS;
    foreach my $record ( @{$newrecordsref} ) {
        $NEWRECORDS{ $record->{'Line'} } = $record;
    }

    my @newzone = ();
    foreach my $record ( @{ $self->{'dnszone'} } ) {
        if ( exists $NEWRECORDS{ $record->{'Line'} } ) {
            push @newzone, $NEWRECORDS{ $record->{'Line'} };
        }
        else {
            push @newzone, $record;
        }
    }
    $self->{'dnszone'} = \@newzone;
    return 1;
}

sub get_first_record {
    my $self      = shift;
    my $recordref = shift;

    foreach my $record ( sort { $a->{'Line'} <=> $b->{'Line'} } @{$recordref} ) {
        return $record;
    }
    return;
}

sub get_record {
    my $self = shift;
    my $line = shift;

    if ( !defined $line || $line < 0 ) {
        return;
    }

    foreach my $record ( @{ $self->{'dnszone'} } ) {
        if ( $line == $record->{'Line'} ) {
            return $record;
        }
    }

    return;
}

sub insert_record_after_line {
    my ( $self, $newrecord, $line ) = @_;

    $self->{'modified'} = 1;
    my $offset          = 0;
    my @newzone         = ();
    my $inserted_record = 0;
    foreach my $record ( @{ $self->{'dnszone'} } ) {
        $record->{'Line'} += $offset;
        push @newzone, $record;
        if ( !$inserted_record && $record->{'Line'} >= $line ) {    #>= accounts for multiline records
            $offset++;
            $newrecord->{'Line'} = ( $record->{'Line'} + 1 );
            push @newzone, $newrecord;
            $inserted_record = 1;
        }
    }

    if ( !$inserted_record ) {    # if we reach the end without inserting just insert it after the last record
        $newrecord->{'Line'} = $#{ $self->{'dnszone'} } == -1 ? 1 : ( $self->{'dnszone'}->[ $#{ $self->{'dnszone'} } ]->{'Line'} + 1 );
        push @newzone, $newrecord;
        $inserted_record = 1;
    }

    $self->{'dnszone'} = \@newzone;
    return;
}

sub remove_records {
    my ( $self, $recordref ) = @_;

    $self->{'modified'} = 1;
    my %REMOVELINES;
    foreach my $record ( sort { $a->{'Line'} <=> $b->{'Line'} } @{$recordref} ) {
        $REMOVELINES{ $record->{'Line'} } = 1;
    }

    my $offset  = 0;
    my @newzone = ();
    foreach my $record ( @{ $self->{'dnszone'} } ) {
        if ( !$REMOVELINES{ $record->{'Line'} } ) {
            $record->{'Line'} -= $offset;
            push @newzone, $record;
        }
        else {
            $offset++;
            next;
        }
    }
    $self->{'dnszone'} = \@newzone;
    return;
}

sub mark_record_for_removal_during_serialize {
    my ( $self, $record ) = @_;

    $self->{'modified'}  = 1;
    $record->{'_delete'} = 1;
    return 1;
}

####################################################################################
#
# Methods:
#   comment_out_records
#
# Description:
#   This method takes in a subset of records from the currently loaded zone and
#   converts them to comments. It will also add an optional comment message as to
#   indicate why the record was commented out.
#
# Parameters:
#   $self               - this object
#   $records_ar         - A subset of records from the currently loaded zone in $self as defined by
#                         Cpanel::Net::DNS::ZoneFile::LDNS or retrieved with $self->find_records_with_names_types_filter
#   $additional_comment - An optional comment to append to the end of each line of the records to be
#                         commented out. If nothing is passed, no additional comment will be added.
#
# Exceptions:
#   None currently.
#
# Returns;
#   Two-arg return.
#   $status - 0 for failure, 1 for success
#   $error  - error message
#
sub comment_out_records {
    my ( $self, $records_ar, $additional_comment ) = @_;

    my %comment_lines = map { $_->{'Line'} => 1 } @$records_ar;

    foreach my $record ( @{ $self->{'dnszone'} } ) {
        next if !$comment_lines{ $record->{'Line'} };
        $self->{'modified'} = 1;

        # Mutates $record
        my ( $status, $message ) = $self->_convert_record_to_comment( $record, $additional_comment );
        return ( 0, $message ) if !$status;
    }

    return 1;
}

sub comment_out_cname_conflicts {
    require Cpanel::ZoneFile::Utils;
    goto \&Cpanel::ZoneFile::Utils::comment_out_cname_conflicts;
}

sub find_records_with_names_types_filter {
    goto \&Cpanel::ZoneFile::Utils::find_records_with_names_types_filter;
}

sub get_modified {
    my ($self) = @_;
    return $self->{'modified'};
}

# Function: _convert_record_to_comment
# $self                  - The object
# $record                - A record as defined by Cpanel::Net::DNS::ZoneFile::LDNS
# $additional_comment    - The comment we will add to the end of each line when we comment out a record
sub _convert_record_to_comment {
    my ( $self, $record, $additional_comment ) = @_;

    my ( $status, $message, $zone_line ) = $self->serialize_single_record($record);
    return ( 0, $message ) if !$status;

    my $multiline = 0;

    # begin each line of a multi-line record with a comment character
    if ( $record->{'Lines'} && $record->{'Lines'} > 1 ) {
        $multiline = 1;
        $zone_line = join( "\n", map { "; $_ ; $additional_comment" } split( "\n", $zone_line ) );
    }

    $record->{'type'} = ':RAW';
    if ( !$multiline ) {
        $record->{'raw'} = '; ' . $zone_line . ( $additional_comment ? ( ' ; ' . $additional_comment ) : q{} );
    }
    else {
        $record->{'raw'} = $zone_line;
    }
    for my $key ( keys %$record ) {
        next if $COMMENT_KEY_LOOKUP{$key};
        delete $record->{$key};
    }

    return 1;
}

sub latlon2dms {
    my ( $lat, $long ) = @_;

    # Using \s here allows newline injection.
    my $pat = qr/^\d+(?:[ \t]+\d+(?:[ \t]\d+(\.\d{1,3})?)?)?[ \t]+[NSEW]$/;
    return ( $lat, $long ) if $lat =~ $pat && $long =~ $pat;
    my $reference_latlon = 2**31;
    my $original_lat     = $lat;
    my $original_long    = $long;
    $lat  -= $reference_latlon;
    $long -= $reference_latlon;
    my ( $latdegval, $latminval, $latsecval ) = dms($lat);
    my $latval = join( ' ', ( $latdegval, $latminval, $latsecval, ( ( $original_lat >= $reference_latlon ) ? 'N' : 'S' ) ) );
    my ( $longdegval, $longminval, $longsecval ) = dms($long);
    my $longval = join( ' ', ( $longdegval, $longminval, $longsecval, ( ( $original_long >= $reference_latlon ) ? 'E' : 'W' ) ) );
    return ( $latval, $longval );
}

sub dms {
    my $val      = shift;
    my $conv_sec = 1000;
    my $conv_min = 60 * $conv_sec;
    my $conv_deg = 60 * $conv_min;
    if ( $val < 0 ) {
        $val = -1 * $val;
    }
    my $degval = int( $val / $conv_deg );
    $val = $val % $conv_deg;
    my $minval = int( $val / $conv_min );
    $val = $val % $conv_min;
    my $secval = sprintf( "%.3f", $val / $conv_sec );
    return ( $degval, $minval, $secval );
}

sub derefalt {
    my $val           = shift;
    my $reference_alt = 100_000 * 100;
    return $val if $val =~ /^\-?\d+(\.\d+)?m$/;
    return ( $val - $reference_alt );
}

sub tomts {
    my $val = shift;
    return $val if $val =~ /^\-?\d+(\.\d+)?m$/;
    return sprintf( "%.2f", ( $val / 100 ) ) . 'm';
}

sub _version_line {
    my $originversion = shift || Cpanel::Version::Full::getversion();
    my $hostname      = Cpanel::Hostname::gethostname();

    return '; cPanel first:' . $originversion . ' latest:' . Cpanel::Version::Full::getversion() . ' Cpanel::ZoneFile::VERSION:' . $VERSION . ' mtime:' . time() . ' hostname:' . $hostname;
}

sub set_method {
    my ( $self, $method ) = @_;
    $self->{'method'} = $method;
    return 1;
}

sub serialize_single_record {
    my ( $self, $record ) = @_;
    my ( $status, $statusmsg, $zonelines_ref ) = $self->dns_zone_obj_to_zonelines( [$record], 'for_display' );
    if ( !$zonelines_ref || !$zonelines_ref->[0] ) {
        return ( 0, "Failed to serialize record: unknown error", '' );
    }
    return ( $status, $statusmsg, $zonelines_ref->[0] );
}

sub dns_zone_obj_to_zonelines {    ## no critic qw(Subroutines::ProhibitExcessComplexity) - this will require a refactor to address.
    my $self        = shift;
    my $dnszone     = shift || $self->{'dnszone'};
    my $for_display = shift;

    $self->{'method'} //= 'arrayref';

    my $has_version_line;
    if ( !$dnszone || !@$dnszone || !$dnszone->[0] ) {
        return ( 0, "dns_zone_obj_to_zonelines requires a dnszone", [], $has_version_line );
    }
    my @zonelines;
    foreach my $record (@$dnszone) {
        if ( !$record->{'type'} || $record->{'_delete'} ) {
            next;
        }
        elsif ( $record->{'type'} eq 'A' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $record->{'address'} );
        }
        elsif ( $record->{'type'} eq 'AAAA' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $record->{'address'} );
        }
        elsif ( $record->{'type'} eq 'AFSDB' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $record->{'subtype'}, $self->_domain( $record->{'hostname'} ) );
        }
        elsif ( $record->{'type'} eq 'DNAME' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $self->_domain( $record->{'dname'} ) );
        }
        elsif ( $record->{'type'} eq 'DS' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $record->{'keytag'}, $record->{'algorithm'}, $record->{'digtype'}, $record->{'digest'} );
        }
        elsif ( $record->{'type'} eq 'HINFO' ) {
            my @hinfo_rdata = map { Cpanel::DnsUtils::RR::encode_character_string( $record->{$_} ) } (qw(cpu os));

            push @zonelines, $self->_build_record( $self->_build_basic_record($record), @hinfo_rdata );
        }
        elsif ( $record->{'type'} eq 'LOC' ) {
            ( $record->{'latitude'}, $record->{'longitude'} ) = latlon2dms( $record->{'latitude'}, $record->{'longitude'} );
            my $loc = $record->{'latitude'} . ' ' . $record->{'longitude'};
            $loc .= ' ' . tomts( derefalt( $record->{'altitude'} ) ) if ( $record->{'altitude'} );
            $loc .= ' ' . tomts( $record->{'size'} )                 if ( $record->{'size'} );
            $loc .= ' ' . tomts( $record->{'horiz_pre'} )            if ( $record->{'horiz_pre'} );
            $loc .= ' ' . tomts( $record->{'vert_pre'} )             if ( $record->{'vert_pre'} );
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $loc );
        }
        elsif ( $record->{'type'} eq 'NAPTR' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $record->{'order'}, $record->{'preference'}, '"' . $record->{'flags'} . '"', '"' . $record->{'service'} . '"', '"' . $record->{'regexp'} . '"', $self->_domain( $record->{'replacement'} ) );
        }
        elsif ( $record->{'type'} eq 'RP' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $record->{'mbox'} . '.', $record->{'txtdname'} . '.' );
        }
        elsif ( $record->{'type'} eq 'SRV' ) {

            # "." is a valid target per RFC 2782
            # add trailing '.' if needed
            my $target = $record->{'target'} eq "." ? $record->{'target'} : $record->{target} . ( substr( $record->{'target'}, -1 ) eq "." ? "" : "." );
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $record->{'priority'}, $record->{'weight'}, $record->{'port'}, $target );
        }
        elsif ( $record->{'type'} eq 'SSHFP' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $record->{'algorithm'}, $record->{'fptype'}, $record->{'fingerprint'} );
        }
        elsif ( $record->{'type'} eq 'TLSA' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $record->{'usage'}, $record->{'selector'}, $record->{'matchingtype'}, $record->{'cert'} );
        }
        elsif ( $record->{'type'} eq 'MX' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $record->{'preference'}, $self->_domain( $record->{'exchange'} ) );
        }
        elsif ( $record->{'type'} eq 'NS' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $self->_domain( $record->{'nsdname'} ) );
        }
        elsif ( $record->{'type'} eq 'CNAME' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $self->_domain( $record->{'cname'} ) );
        }
        elsif ( $record->{'type'} eq 'PTR' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $self->_domain( $record->{'ptrdname'} ) );
        }
        elsif ( $record->{'type'} eq 'TXT' || $record->{'type'} eq 'SPF' ) {
            $record->{'type'} = 'TXT' if $record->{'type'} eq 'SPF';    # force SPF record types to be TXT records.
            push @zonelines, $self->_build_record(
                $self->_build_basic_record($record),
                $record->{'unencoded'}
                ? Cpanel::DnsUtils::RR::encode_and_split_dns_txt_record_value( $record->{'txtdata'} )
                : $record->{'txtdata'}
            );
        }

        #We never know how many lines the SOA entry takes up,
        #so we pad/constrict as needs be so that line numbers
        #in the serialized zone file will match those in the original.
        #If no 'Lines' property is given, or if we want pretty printing,
        #default to 7 lines (per convention).
        elsif ( $record->{'type'} eq 'SOA' ) {
            my $lines    = ( !$self->{'pretty_print'} && $record->{'Lines'} ) || $DEFAULT_SOA_LINES_PER_CONVENTION;
            my @newlines = ("\n") x ( $lines - 1 );
            push @zonelines,
              $self->_build_record(
                $self->_build_basic_record($record),
                $record->{'mname'} . '.',
                $record->{'rname'} . '.', '(' . ( shift(@newlines) || q{} ),
                "\t" x 5 . $record->{'serial'} .  ( ( shift(@newlines) || q{} ) ? " ;Serial Number\n" : q{} ),
                "\t" x 5 . $record->{'refresh'} . ( ( shift(@newlines) || q{} ) ? " ;refresh\n"       : q{} ),
                "\t" x 5 . $record->{'retry'} .   ( ( shift(@newlines) || q{} ) ? " ;retry\n"         : q{} ),
                "\t" x 5 . $record->{'expire'} .  ( ( shift(@newlines) || q{} ) ? " ;expire\n"        : q{} ),
                "\t" x 5 . $record->{'minimum'} . ( ( shift(@newlines) || q{} ) ? " ;minimum\n"       : q{} ),
                ')' . ( join( q{}, @newlines ) ),
              );
        }
        elsif ( $record->{'type'} eq ':RAW' ) {
            if ( index( $record->{'raw'}, 'cPanel' ) > -1 && $record->{'raw'} =~ $Cpanel::ZoneFile::Versioning::STARTMATCH ) {
                my $originversion = $1;
                push @zonelines, Cpanel::ZoneFile::Versioning::version_line( $originversion, $self->{'update_time'}, $self->{'hostname'} );
                $has_version_line = 1;
            }
            else {
                push @zonelines, $record->{'raw'};
            }
        }
        elsif ( $record->{'type'} eq '$TTL' ) {
            push @zonelines, '$TTL ' . ( $record->{'ttl'} || $FALLBACK_TTL );
            $self->{'defaultttl'} = $record->{'ttl'};
        }
        elsif ( $record->{'type'} eq 'A6' ) {
            push @zonelines, $self->_build_record( $self->_build_basic_record($record), $record->{'prefix'}, $record->{'address'}, $record->{'refer'} );
        }
        elsif ( $record->{'type'} eq 'CAA' || $record->{'type'} eq 'TYPE257' ) {
            $record->{'type'} = $for_display ? 'CAA' : 'TYPE257';
            push @zonelines, $self->_build_record(
                $self->_build_basic_record($record),
                (
                    $for_display
                    ? ( $record->{'flag'}, $record->{'tag'}, '"' . $record->{'value'} . '"' )
                    : ( $record->{'value_legacy'} )
                )
            );
        }
        else {
            my $record_type = $record->{'type'} || 'UNKNOWN';
            Cpanel::Debug::log_warn("Unsupported record : $record_type");
            return ( 0, "Unsupported record : $record_type", [], $has_version_line );
        }
    }
    return ( 1, "Build zonelines ok", \@zonelines, $has_version_line );
}

sub build_zone {
    return $_[0]->_build_zone();
}

sub build_zone_for_display {
    return $_[0]->_build_zone('for_display');
}

sub _build_zone {
    my $self        = shift;
    my $for_display = shift;

    my ( $status, $statusmsg, $zonelines_ref, $has_version ) = $self->dns_zone_obj_to_zonelines( undef, $for_display );
    if ( !$has_version ) { unshift @$zonelines_ref, Cpanel::ZoneFile::Versioning::version_line( '', $self->{'update_time'}, $self->{'hostname'} ); }
    push @$zonelines_ref, '';    #dns requires a newline at the end of the file
    return wantarray ? @$zonelines_ref : $zonelines_ref;
}

sub to_zone_string {
    return join( "\n", @{ $_[0]->_build_zone() } );
}

sub increase_serial_number {
    my ($self) = @_;
    my $new_serial = Cpanel::Time::time2dnstime() . '00';

    my @records = $self->find_records( { 'type' => 'SOA' } );
    return 0, 'Unable to find SOA record.' if !scalar @records;

    my ($soa) = @records;
    my $old_serial = $soa->{'serial'};

    if ( $new_serial > $old_serial ) {
        $soa->{'serial'} = $new_serial;
    }
    else {
        $soa->{'serial'} = $old_serial + 1;
    }

    return 1, 'Incremented Serial', $soa->{'serial'};
}

sub _build_basic_record {

    # Collapsing the ttl confuses users so we no longer do it
    return ( $_[0]->_collapse_name( $_[1]->{'name'} ), ( $_[0]->{'forcedttl'} || $_[1]->{'ttl'} || $_[0]->{'defaultttl'} ), $_[1]->{'class'} // 'IN', $_[1]->{'type'} );
}

sub _build_record {
    return $_[0]->{'method'} eq 'text' ? join( "\t", @_[ 1 .. $#_ ] ) : [ @_[ 1 .. $#_ ] ];

    #allocate a new array so we are not messing the reference to our zonedata
}

sub _domain {
    return substr( $_[1], -1 ) eq '.' ? $_[1] : $_[1] . '.';
}

sub forcettl {
    return ( $_[0]->{'forcedttl'} = $_[1] );
}

sub _collapse_name {
    return

      # Does not end with .$zoneroot.
      (
        !defined $_[0]->{'zoneroot'} ||                                                          #
          $_[0]->{'zoneroot_trailer_length'} > length( $_[1] ) ||                                #
          substr( $_[1], -$_[0]->{'zoneroot_trailer_length'} ) ne $_[0]->{'zoneroot_trailer'}    #
      )                                                                                          #
      ?                                                                                          #
      $_[1]

      # Ends with .$zoneroot.
      : substr( $_[1], 0, -$_[0]->{'zoneroot_trailer_length'} );
}

# remove all AAAA records that are one of the provided list of IPv6 address
sub _remove_IPv6_records_by_address {
    my ( $self, %opts ) = @_;

    # do not proceed if ipv6_addresses_to_remove is empty
    return if not exists $opts{ipv6_addresses_to_remove} or q{ARRAY} ne ref $opts{ipv6_addresses_to_remove} or 0 == @{ $opts{ipv6_addresses_to_remove} };

    # get all AAAA records
    my @AAAA_records_to_remove = $self->find_records_with_names_types_filter( [qw/AAAA/] );

    # filter out AAAA records to keep, i.e., those with IPv6 addresses that are not a related IP
    if (@AAAA_records_to_remove) {
        my $index = $#AAAA_records_to_remove;
        require Cpanel::CPAN::Net::IP;
      REMOVE_AAAA_RECORDS_TO_KEEP:
        foreach my $record ( reverse @AAAA_records_to_remove ) {

            # normalize IPv6 format for proper comparison
            my $address = Cpanel::CPAN::Net::IP::ip_compress_address( $record->{'address'}, 6 );

            # if $address is not a related IPv6 address, remove from @AAAA_records_to_remove so it doesn't get removed in last step
            if ( not grep { $address eq Cpanel::CPAN::Net::IP::ip_compress_address( $_, 6 ) } @{ $opts{ipv6_addresses_to_remove} } ) {
                splice @AAAA_records_to_remove, $index, 1;
            }
            --$index;
        }
    }

    # remove any remaining AAAA records, since they are associated with the related IPv6 addresses
    $self->remove_records( \@AAAA_records_to_remove ) if @AAAA_records_to_remove;
    return \@AAAA_records_to_remove;
}

# replace all AAAA with matching a related ip address with the provided new IPv6 address
# by first deleting old records, then adding them back with updated IPv6 address
sub _swap_IPv6_records_by_address {
    my ( $self, %opts ) = @_;

    # do not proceed if ipv6_addresses_to_replace or new_ipv6 is empty
    return if not $opts{new_ipv6} or not exists $opts{ipv6_addresses_to_replace} or q{ARRAY} ne ref $opts{ipv6_addresses_to_replace} or 0 == @{ $opts{ipv6_addresses_to_replace} };

    my $new_ipv6 = $opts{new_ipv6};

    # remove unwanted records, in return get list of AAAA records that need to be added back with $new_ipv6
    my $records_to_replace = $self->_remove_IPv6_records_by_address( 'ipv6_addresses_to_remove' => $opts{ipv6_addresses_to_replace} );

    # add new records - Assumed to be only AAAA records, since it is starting with copies of the records
    # that were removed and returned in teh call to _remove_IPv6_records_by_address above
    foreach my $record (@$records_to_replace) {
        $record->{'address'} = $new_ipv6;
        $self->add_record($record);
    }

    return;
}

1;
