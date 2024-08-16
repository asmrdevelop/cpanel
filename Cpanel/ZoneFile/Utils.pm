package Cpanel::ZoneFile::Utils;

# cpanel - Cpanel/ZoneFile/Utils.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::IP::Match ();

my @COMMON_RECORD_KEYS      = qw( ttl name );
my %RECORD_COMPARISONS_KEYS = (
    'SOA' => {
        'keys' => [ @COMMON_RECORD_KEYS, qw( expire minimum mname refresh retry rname ) ],
    },
    'NS' => {
        'keys' => [ @COMMON_RECORD_KEYS, 'nsdname' ],
    },
    'A' => {
        'keys'    => [ @COMMON_RECORD_KEYS, 'address' ],
        'address' => \&Cpanel::IP::Match::ips_are_equal,
    },
    'AAAA' => {
        'keys'    => [ @COMMON_RECORD_KEYS, 'address' ],
        'address' => \&Cpanel::IP::Match::ips_are_equal,
    },
    'CNAME' => {
        'keys' => [ @COMMON_RECORD_KEYS, 'cname' ],
    },
    'MX' => {
        'keys' => [ @COMMON_RECORD_KEYS, qw( preference exchange ) ],
    },
);

#############################################################################################
########################## MEMBER FUNCTIONS #################################################
#############################################################################################

####################################################################################
#
# Methods:
#   comment_out_cname_conflicts
#
# Description:
#   This function will look for records in a zone that conflict with any CNAME record in the zone.
#   It will then comment out the conflicting CNAME record. It will also remove multiple CNAME
#   records with the same labels.
#
# Parameters:
#   $zone_obj      - A Cpanel::ZoneFile object that may have its records modified if conflicts are detected.
#   $merge_comment - An optional comment to be appended to the commented out records.
#
# Exceptions:
#   None currently.
#
# Returns;
#   A list of the names of modified records
#
sub comment_out_cname_conflicts {
    my ( $zone_obj, $merge_comment ) = @_;

    my @records_to_comment            = ();
    my $all_records_ar                = $zone_obj->find_records();
    my @conflicting_non_cname_records = grep { $_->{'type'} && $_->{'type'} ne 'CNAME' && !_is_type_cname_compatible( $_->{'type'} ) } @$all_records_ar;
    my @modified_record_names;

    # make sure order does not matter for all but CNAME records
    my %seen_name = (
        map { $_->{'name'} ? ( $_->{'name'} => 1 ) : () } @conflicting_non_cname_records,
    );

    for my $record (@$all_records_ar) {
        next if !$record->{'name'};
        next if _is_type_cname_compatible( $record->{'type'} );

        # check for CNAMEs that collide with other CNAMEs too
        if ( !$seen_name{ $record->{'name'} } ) {
            $seen_name{ $record->{'name'} } = 1;
            next;
        }
        elsif ( $seen_name{ $record->{'name'} } && $record->{'type'} eq 'CNAME' ) {
            push @modified_record_names, $record->{'name'};
            push @records_to_comment,    $record;
        }
    }

    if (@records_to_comment) {
        $zone_obj->comment_out_records( \@records_to_comment, $merge_comment );
    }

    return (@modified_record_names);
}

####################################################################################
#
# Methods:
#   find_records_with_names_types_filter
#
# Description:
#   This function will search a Cpanel::ZoneFile object for records matching the search parameters.
#   Each parameter needs to be a match for a record to return. Undef may be passed to ignore a search term.
#   Passing in only a $zone_obj (no search terms) will return the entire collection of records for the zone.
#
# Parameters:
#   $zone_obj          - A Cpanel::ZoneFile object.
#   $resource_types_ar - An optional array ref of record type names to match against the records in
#                        $zone_obj. To not specify a type to search for, pass undef.
#                        NOTE: record types are case sensitive
#   $resource_names_ar - An optional array ref of fully qualified record label names to match against the
#                        records in $zone_obj. To not specify a label name to search for, pass undef.
#                        NOTE: label names are case sensitive
#                        NOTE2: Remember to include the trailing period if the label has one.
#   $filter_cr         - An optional coderef used to filter the zones in $zone_obj. The coderef will receive
#                        only the record as input and should return 1 if the record should be returned and 0
#                        if the record should not be returned.
#
# Exceptions:
#   None currently.
#
# Returns;
#   Returns a list of matching records.
#
sub find_records_with_names_types_filter {
    my ( $zone_obj, $resource_types_ar, $resource_names_ar, $filter_cr ) = @_;

    my @records = ();

    if ($resource_types_ar) {
        for my $resource_type (@$resource_types_ar) {
            if ($resource_names_ar) {
                for my $resource_name (@$resource_names_ar) {
                    push @records, _find_records( $zone_obj, $resource_type, $resource_name, $filter_cr );
                }
            }
            else {
                push @records, _find_records( $zone_obj, $resource_type, undef, $filter_cr );
            }
        }
    }
    elsif ($resource_names_ar) {
        for my $resource_name (@$resource_names_ar) {
            push @records, _find_records( $zone_obj, undef, $resource_name, $filter_cr );
        }
    }
    else {
        push @records, _find_records( $zone_obj, undef, undef, $filter_cr );
    }

    return @records;
}

sub _find_records {
    my ( $zone_obj, $resource_type, $resource_name, $filter_cr ) = @_;

    my $unfiltered_records_ar = $zone_obj->find_records(
        {
            ( $resource_type ? ( 'type' => $resource_type ) : () ),
            ( $resource_name ? ( 'name' => $resource_name ) : () ),
        }
    );

    if ( $filter_cr && ref $filter_cr eq 'CODE' ) {
        return ( grep { $filter_cr->($_) } @$unfiltered_records_ar );
    }
    return @$unfiltered_records_ar;
}

#############################################################################################
########################## STATIC FUNCTIONS #################################################
#############################################################################################

####################################################################################
#
# Methods:
#   are_records_equivalent
#
# Description:
#   This function will compare two passed in records for equivalence.
#
# Parameters:
#   $first_record  - LHS - first record to compare.
#   $second_record - RHS - second record to compare.
#
# Exceptions:
#   A die will occur if an unsupported record type is passed in, please see %RECORD_COMPARISON_KEYS.
#
# Returns;
#   Returns 1 if the records are equivalent or 0 if they are not.
#
sub are_records_equivalent {
    my ( $first_record, $second_record ) = @_;

    return 0 if !$first_record || !$second_record;
    return 0 if $first_record->{'type'} ne $second_record->{'type'};
    my $type = $first_record->{'type'};

    # programmer error, add to %RECORD_COMPARISON_KEYS if more comparison types are desired
    die "Untracked record type!" if !$RECORD_COMPARISONS_KEYS{$type};

    for my $key ( @{ $RECORD_COMPARISONS_KEYS{$type}{'keys'} } ) {
        my $comparison_cr = $RECORD_COMPARISONS_KEYS{$type}{$key};
        if ($comparison_cr) {
            return 0 if !$comparison_cr->( $first_record->{$key}, $second_record->{$key} );
        }
        else {
            return 0 if $first_record->{$key} ne $second_record->{$key};
        }
    }

    return 1;
}

# This will return true if the passed in type will not conflict with a CNAME record of the same label
# see http://tools.ietf.org/html/rfc1912 section 2.4
sub _is_type_cname_compatible {
    return ( $_[0] eq ':RAW' || $_[0] eq '$TTL' ) ? 1 : 0;    # See Cpanel::ZoneFile
}

1;
