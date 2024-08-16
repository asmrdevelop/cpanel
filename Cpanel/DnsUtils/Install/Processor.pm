package Cpanel::DnsUtils::Install::Processor;

# cpanel - Cpanel/DnsUtils/Install/Processor.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Whostmgr::Transfers::State ();

use Cpanel::ZoneFile::Collection        ();
use Cpanel::DnsUtils::AskDnsAdmin       ();
use Cpanel::DnsUtils::Install::Template ();
use Cpanel::Domain::Zone                ();
use Cpanel::Debug                       ();

our $VERSION = 1.1;

our $FAILURE_STRING      = 'FAIL:';
our $NO_CHANGES_STRING   = 'no changes needed';
our $MISSING_ZONE_STRING = 'missing zone';

our $STATUS_TOTAL_FAILURE   = 0;
our $STATUS_SUCCESS         = 1;
our $STATUS_PARTIAL_SUCCESS = 2;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Install::Processor - Internals for Cpanel::DnsUtils::Install

=head1 SYNOPSIS

    use Cpanel::DnsUtils::Install::Processor ();

    Cpanel::DnsUtils::Install::Processor->_process_dnsrecord_operations(
          'pre_fetched_zones' => {
                                     'yxikemoyznvljzpoeiqw.org' => [ "zone", "contents", "here", .... ],
                                     'fjmgams9.cptest' => undef
                                   },
          'reload' => 0,
          'dns_record_operations' => {
                                       'pickles.px3nfikw.cptest.' => [
                                                                       [
                                                                         {
                                                                           'domain' => '%domain%',
                                                                           'operation' => 'add',
                                                                           'domains' => 'all',
                                                                           'value' => '%ip%',
                                                                           'type' => 'A',
                                                                           'record' => 'pickles.%domain%'
                                                                         }
                                                                       ],
                                                                       'px3nfikw.cptest'
                                                                     ],
                                       'pickles.woqatmjgkkuxljbgofyk.org.' => [
                                                                                [
                                                                                  {
                                                                                    'domain' => '%domain%',
                                                                                    'operation' => 'add',
                                                                                    'domains' => 'all',
                                                                                    'value' => '%ip%',
                                                                                    'type' => 'A',
                                                                                    'record' => 'pickles.%domain%'
                                                                                  }
                                                                                ],
                                                                                'woqatmjgkkuxljbgofyk.org'
                                                                              ]
                                     },
          'replace_records' => 1
        }
    );

=head1 DESCRIPTION

This module is not intended to be called directly as it serves as the
internals for Cpanel::DnsUtils::Install

This module serves as the backend for Cpanel::DnsUtils::Install
it should not be called from outside of Cpanel::DnsUtils::Install

Constants for $dns_record_operations_hr

Since we can be interested in many records at a time
this structure is hashref of arrayrefs with
constants as the key names in order to save memory

 [
   '$name' => [
     OPERATIONS                [ {...}, {...}, ... ]   This is an arrayref of operations (as hashrefs) to be completed by the processor
     DOMAIN                    domain                  This is the domain used in the template to construct OPERATIONS
     TARGET_ZONE               zone                    This is the zone that the $name record SHOULD be saved in.
     OPERATIONS_COMPLETED      [ undef, 1, ...     ]   This is an arrayref to track which operations have already been completed
   ],
   ......
 ]

 Example OPERATIONS:
 [
   {
      'operation' => 'add',
      'domain' => '%domain%',
      'value' => 'v=spf1 +a +mx +ip4:10.215.215.232 ~all',
      'type' => 'TXT',
      'removematch' => 'v=spf1 +a +mx +ip4:10.215.215.232 ~all',
      'record' => '%domain%',
      'match' => 'v=spf'
   },
   ...
 ]

For a detailed explanation of the inputs for OPERATIONS see
See 'structure of record operations' in the NOTES section
of Cpanel::DnsUtils::Install

NOTE: The hashref sent to dns_record_operations will be modified by this function!!

=head2 Outputs from C<_process_dnsrecord_operations()>

This outputs three things:

=over

=item * A redundant status code. (See below.)

=item * A redundant string that consists of each entry in
C<errors> (below) concatenated by a newline.  The caller is encourged to check
C<domain_status> and should genreally ignore this field except for debugging
purposes.

=item * A hashref:

=over

=item * C<status> - A redundant indicator of failure, success, or partial
success. See the C<$STATUS_TOTAL_FAILURE>, C<$STATUS_SUCCESS>, and
C<$STATUS_PARTIAL_SUCCESS> constants in Processor.pm. “Failure” means
every operation failed, “success” means they all succeeded”; any other
state is “partial success”. (This is the same value as the function’s
first return, above.)

=item * C<errors> - Arrayref of strings.  The caller is encourged to check
C<domain_status> and should genreally ignore this field except for debugging
purposes.

=item * C<zones_modified> - Arrayref of strings.

=item * C<domain_status> - Arrayref of hashes. Each hash is:

=over

=item * C<domain> - The individual domain name for which an operation happened.

=item * C<status> - Boolean to indicate success or failure of the operation.

=item * C<msg> - A parsable string. It begins with a left bracket (C<[>).
Then, in case of failure (and only then), the string will include
C<$Cpanel::DnsUtils::Install::Processor::FAILURE_STRING>. After that comes a
comma-separated list of messages meant for human consumption. Finally, it
concludes with a right bracket (C<]>).

=back

=back

=back

As C<errors> is only a collection of all the errors that happen during the
install process, callers should examine C<domain_status> to determine if
there was a failure to install records for a given domain.

=cut

use constant OPERATIONS           => 0;
use constant DOMAIN               => 1;
use constant TARGET_ZONE          => 2;
use constant OPERATIONS_COMPLETED => 3;

use constant MISSING_ZONE => 0;
use constant HAS_ZONE     => 1;

# This is only intended to be called from  Cpanel::DnsUtils::Install
sub _process_dnsrecord_operations {
    my ( $class, %OPTS ) = @_;

    # reload:
    # Perform a RELOADZONES for modified zones if true
    my $reload = $OPTS{'reload'};

    # pre_fetched_zones (optional):
    # A hashref of zones that have already been fetched
    # Any empty zones will be fetched using
    # Cpanel::DnsUtils::Fetch::fetch_zones
    # Example
    # {
    #   'zone1.tld' => [ raw zone conents, ... ],
    #   'zone2.tld' => undef,
    #   'zone3.tld' => [ raw zone conents, ... ],
    #   ...
    #
    # }
    my $pre_fetched_zones = $OPTS{'pre_fetched_zones'};

    # replace_records:
    # 1 or 0 if the system should replace
    # existing records that match using the params
    # in each dns_record_operations operation
    my $replace_records = $OPTS{'replace_records'};

    # dns_record_operations:
    # See above for the format
    #
    # Warning: this function will mutate this structure
    # as it requires too much memory to make a copy of
    # it when there are a large number of domains.
    my $dns_record_operations = $OPTS{'dns_record_operations'};

    my $self = bless {

        # INPUTS
        'dns_record_operations_hr' => $dns_record_operations,
        'replace_records'          => $replace_records,
        %OPTS{'ttl'},

        # CACHE
        '_cache' => {},

        # ZONE STATE
        'zone_file_objs_hr' => {},
        'all_records_hr'    => undef,

        # OUTPUTS
        'error_messages_ar'  => [],
        'zone_operations_hr' => {},
    }, $class;

    my $status;

    my $zones_modified_ar;

    try {
        {    # Prep work
             # First load all the zones
             # _load_zones_and_find_zone_targets
             # Fills the TARGET_ZONE field in $dns_record_operations_hr
             # Supplies the lists of zones to enumerate and parse to $self->{zone_file_objs_hr}
             #
            $self->_load_zones_and_find_op_zone_targets($pre_fetched_zones);

            # Its possible that we do not have a few zones so we must remove the records
            # that have no target zone
            $self->_prune_operations_that_do_not_have_a_zone_to_operate_on();
        }

        {    # Modify the zones in memory as needed
             # Do updates as needed
            $self->_update_or_delete_existing_records_from_all_possible_zones();

            $self->_add_records_that_do_not_already_exist();
        }

        # Save all the zones and return status
        $zones_modified_ar = $self->_update_and_reload_modified_dns_zones($reload);
    }
    catch {
        $status = 0;
        push @{ $self->{'error_messages_ar'} }, $_;
    };

    #
    # API return compatible with install_records
    #

    # Clean up as soon as possible
    delete @{$self}{ 'zone_file_objs_hr', 'dns_record_operations_hr' };

    my $domain_status = $self->_create_domain_status_from_dns_record_operations();

    if ($zones_modified_ar) {
        my $success_count = 0;

        # This used to be scalar @{ $self->{'error_messages_ar'} }, but it’s duplicative of 'status'.
        my $failure_count = 0;

        $_->{'status'} ? $success_count++ : $failure_count++ for (@$domain_status);

        $status = $failure_count ? ( $success_count ? $STATUS_PARTIAL_SUCCESS : $STATUS_TOTAL_FAILURE ) : $STATUS_SUCCESS;
    }

    return (
        $status,
        join( "\n", @{ $self->{'error_messages_ar'} } ),
        {
            'status'         => $status,
            'zones_modified' => $zones_modified_ar,
            'domain_status'  => $domain_status,
            'errors'         => $self->{'error_messages_ar'},

            # We used to return a redundant “reload_list” here that
            # was just ( $reload ? [] : $zones_modified_ar ). There’s
            # no point in returning this since the caller can do that
            # logic easily enough, and nothing was using it.
        }
    );
}

## -- support functions for  _process_dnsrecord_operations -- ##

sub _add_error {
    my ( $self, $msg ) = @_;
    my $errors = $self->{'error_messages_ar'};
    my @caller = caller();
    push @$errors, ( caller(0) )[0] . ':' . ( caller(0) )[2] . ': ' . $msg;
    Cpanel::Debug::log_warn( ( caller(0) )[3] . ': ' . $msg );
    return;
}

sub _update_and_reload_modified_dns_zones {
    my ( $self, $do_reload ) = @_;

    #
    ##
    my ( $synczones_request, $zones_modified_ar ) = $self->_generate_dnsadmin_operations_from_modified_zones();
    #
    # Special case to handle transfers
    #
    # Account Restorations do local only because a DNS cluster sync
    # happens at the end of the restoration.
    my $_dns_local = Whostmgr::Transfers::State::is_transfer() ? $Cpanel::DnsUtils::AskDnsAdmin::LOCAL_ONLY : $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL;

    if ( keys %$synczones_request ) {
        Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'SYNCZONES', $_dns_local, '', '', '', $synczones_request );
        if ( $do_reload && @$zones_modified_ar ) {
            Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADZONES', $_dns_local, join( ',', @$zones_modified_ar ) );
        }
    }
    #
    return $zones_modified_ar;
}

sub _generate_dnsadmin_operations_from_modified_zones {
    my ($self) = @_;

    my $zone_file_objs_hr = $self->{'zone_file_objs_hr'};
    my @RELOAD_LIST;
    my %SYNCZONES_request;
    foreach my $zone ( keys %$zone_file_objs_hr ) {
        my $zonefile_obj = $zone_file_objs_hr->{$zone};
        next if !$zonefile_obj->get_modified();

        $zonefile_obj->increase_serial_number();

        my $zonedata = $zonefile_obj->to_zone_string();
        $SYNCZONES_request{"cpdnszone-$zone"} = $zonedata;
        push @RELOAD_LIST, $zone;
    }

    return ( \%SYNCZONES_request, \@RELOAD_LIST );
}

sub _update_or_delete_existing_records_from_all_possible_zones {
    my ($self) = @_;
    my ( $zone_file_objs_hr, $dns_record_operations_hr, $zone_operations_hr ) =
      @{$self}{qw(zone_file_objs_hr dns_record_operations_hr zone_operations_hr)};

    foreach my $zone ( sort { length $b <=> length $a } keys %$zone_file_objs_hr ) {
        my $zonefile_obj      = $zone_file_objs_hr->{$zone};
        my $dnszone           = $zonefile_obj->{'dnszone'};
        my $number_of_records = scalar @$dnszone;
        foreach ( grep { $_->{'name'} && $dns_record_operations_hr->{ $_->{'name'} } } @$dnszone ) {
            $self->_process_operations_on_matched_dnszone_entry(
                'name'          => $_->{'name'},
                'zone'          => $zone,
                'dnszone_entry' => $_,
                'zonefile_obj'  => $zonefile_obj,
            );
        }
    }
    return;
}

sub _process_operations_on_matched_dnszone_entry {
    my ( $self, %OPTS ) = @_;

    my ( $name, $zone, $zonefile_obj, $dnszone_entry ) = @OPTS{qw(name zone zonefile_obj dnszone_entry)};
    my ( $dns_record_operations_hr, $zone_operations_hr, $replace_records ) =
      @{$self}{qw(dns_record_operations_hr zone_operations_hr replace_records)};
    my $shortname = $zonefile_obj->_collapse_name($name);

    my ( $domain, $operations, $target_zone, $operations_completed ) =
      @{ $dns_record_operations_hr->{$name} }[ DOMAIN, OPERATIONS, TARGET_ZONE, OPERATIONS_COMPLETED ];

    my $zone_record_type = $dnszone_entry->{'type'};

    my $template_obj = Cpanel::DnsUtils::Install::Template->new( { 'domain' => $domain }, $self->{'_cache'} );

    my $number_of_operations = scalar @$operations;
  OPERATION:
    for ( my $op_idx = 0; $op_idx < $number_of_operations; $op_idx++ ) {
        my $operation      = $operations->[$op_idx];
        my $op_record_type = $operation->{'type'};
        if ( $op_record_type ne $zone_record_type ) {
            next OPERATION;
        }

        my $match       = length $operation->{'match'}       ? $template_obj->process( $operation->{'match'} )                     : undef;
        my $removematch = length $operation->{'removematch'} ? ( $template_obj->process( $operation->{'removematch'} ) // $match ) : $match;

        my $results = ( $zone_operations_hr->{$zone} ||= [] );

        my $current_zone_record_value = $zonefile_obj->get_zone_record_value($dnszone_entry);

        if ( $operation->{'operation'} eq 'add' ) {
            if ( !$replace_records ) {

                # Existing record, but replace_records not set
                $operations_completed->[$op_idx]++;
                next OPERATION;
            }
            elsif ( !_match_any( $current_zone_record_value, $match ) ) {

                # No match
                next OPERATION;
            }
            elsif ( $zone ne $target_zone ) {
                #
                # !!AUTOMATIC FIX OF RECORD IN THE WRONG ZONE!!
                # when replace_records is set
                #
                # If the record is in the wrong zone file, we need to move
                # it to the correct zone file
                $zonefile_obj->mark_record_for_removal_during_serialize($dnszone_entry);
                push @$results, [ 1, "WRONGZONE:$op_record_type\@$shortname", $domain ];
            }
            elsif ( $operations_completed->[$op_idx] ) {
                unless ( $operation->{'keep_duplicate'} ) {

                    # If there are multiple records for this name we remove the
                    # duplicates by splicing in ''
                    $zonefile_obj->mark_record_for_removal_during_serialize($dnszone_entry);
                    push @$results, [ 1, "REMOVEDUPE:$op_record_type\@$shortname", $domain ];
                }
            }
            elsif ( _match_any( $current_zone_record_value, $removematch ) ) {
                $self->_perform_record_replacement(
                    'zonefile_obj'              => $zonefile_obj,
                    'dnszone_entry'             => $dnszone_entry,
                    'template_obj'              => $template_obj,
                    'current_zone_record_value' => $current_zone_record_value,
                    'operation'                 => $operation,
                    'results'                   => $results,
                    'shortname'                 => $shortname,
                    'domain'                    => $domain,
                );

                $operations_completed->[$op_idx]++;
            }
            else {
                # We saw it, we didn't have a matcher to replace/remove it
                # and its in the right zone so do nothing
                $operations_completed->[$op_idx]++;
            }
        }
        elsif ( $operation->{'operation'} eq 'delete' ) {
            if ( _match_any( $current_zone_record_value, $removematch ) ) {
                $zonefile_obj->mark_record_for_removal_during_serialize($dnszone_entry);
                push @$results, [ 1, "REMOVE:$op_record_type\@$shortname:$current_zone_record_value", $domain ];
                next;
            }
        }
        else {
            push @$results, [ 0, "Invalid operation '$operation->{'operation'}' requested for $domain", $domain ];
        }
    }
    return;
}

sub _perform_record_replacement {
    my ( $self, %OPTS ) = @_;

    my ( $zonefile_obj, $dnszone_entry, $template_obj, $operation, $current_zone_record_value, $shortname, $results, $domain ) = @OPTS{qw(zonefile_obj dnszone_entry template_obj operation current_zone_record_value shortname results domain)};
    my $value = $template_obj->process( $operation->{'value'} );
    if ( !$value ) {
        push @$results, [ 0, "Could not resolve empty value: “$operation->{'value'}”", $domain ];
        return;
    }
    my $transform      = $operation->{'transform'};
    my $op_record_type = $operation->{'type'};

    if ( ref $transform eq 'CODE' ) {
        local $@;
        eval {
            # Transform is responsible for calling set_zone_record_value
            $transform->( $zonefile_obj, $dnszone_entry, $template_obj );

            my $transformed_zone_record_value = $zonefile_obj->get_zone_record_value($dnszone_entry);

            if ( $current_zone_record_value ne $transformed_zone_record_value ) {
                push @$results, [ 1, "REPLACE:$op_record_type\@$shortname:$value", $domain ];
            }
        };
        if ($@) {
            $self->_add_error("Failed to transform “$shortname” in “$zonefile_obj->{'rootdomain'}” because of an error: $@");
        }
    }
    elsif ( $current_zone_record_value ne $value ) {
        $zonefile_obj->set_zone_record_value( $dnszone_entry, $value );

        $dnszone_entry->{'ttl'} = $self->{'ttl'} if $self->{'ttl'};

        push @$results, [ 1, "REPLACE:$op_record_type\@$shortname:$value", $domain ];
    }
    return;
}

sub _op_has_cname_conflict {
    my ( $self, %OPTS ) = @_;

    my ( $name, $operation, $results, $domain ) = @OPTS{qw(name operation results domain)};

    if ( !$self->{'all_records_hr'} ) {
        $self->_create_all_record_map_for_zones();
    }
    my $all_records_hr = $self->{'all_records_hr'};

    my $op_record_type = $operation->{'type'};
    if ( $op_record_type ne 'CNAME' && $all_records_hr->{$name}{'CNAME'} ) {
        push @$results, [ 0, qq{The “$op_record_type” record for “$name” could not be added because it would conflict with the existing “CNAME” record.}, $domain ];
        return 1;
    }
    elsif ( $op_record_type eq 'CNAME' ) {
        my @all_types_for_this_name_except_cname = grep { $_ ne 'CNAME' } keys %{ $all_records_hr->{$name} };
        if (@all_types_for_this_name_except_cname) {
            push @$results, [ 0, qq{The “CNAME” record for “$name” could not be added because it would conflict with the existing “@all_types_for_this_name_except_cname” record(s).}, $domain ];
            return 1;
        }
    }

    return 0;
}

sub _create_domain_status_from_dns_record_operations {
    my ($self) = @_;

    my ( $dns_record_domains_hr, $dns_record_operations_hr, $zone_operations_hr ) =
      @{$self}{qw(dns_record_domains_hr dns_record_operations_hr zone_operations_hr)};

    my %domain_status;
    foreach my $zone ( keys %$zone_operations_hr ) {
        foreach my $op_ref ( @{ $zone_operations_hr->{$zone} } ) {
            my ( $status, $msg, $domain ) = @{$op_ref};
            $domain_status{$domain}->[0] ||= $status;
            push @{ $domain_status{$domain}->[1] }, $msg;
        }
    }
    foreach my $domain ( grep { !$domain_status{$_} } keys %$dns_record_domains_hr ) {
        my $has_zone = $dns_record_domains_hr->{$domain} == HAS_ZONE ? 1 : 0;
        $domain_status{$domain} = [
            $has_zone,
            [ $has_zone ? $NO_CHANGES_STRING : $MISSING_ZONE_STRING ]
        ];
    }
    return [
        map {
            {
                'status' => $domain_status{$_}->[0],
                'domain' => $_,

                # Callers look for the string $FAILURE_STRING
                'msg' => "[" . ( $domain_status{$_}->[0] ? '' : $FAILURE_STRING ) . join( ', ', @{ $domain_status{$_}->[1] } ) . "]",
            }
        } sort keys %domain_status
    ];
}

sub _add_records_that_do_not_already_exist {
    my ($self) = @_;
    my ( $dns_record_operations_hr, $zone_file_objs_hr, $zone_operations_hr ) =
      @{$self}{qw(dns_record_operations_hr zone_file_objs_hr zone_operations_hr)};
    foreach my $name ( keys %$dns_record_operations_hr ) {
        my ( $operations, $domain, $target_zone, $operations_completed ) =
          @{ $dns_record_operations_hr->{$name} }[ OPERATIONS, DOMAIN, TARGET_ZONE, OPERATIONS_COMPLETED ];
        my $template_obj         = Cpanel::DnsUtils::Install::Template->new( { 'domain' => $domain }, $self->{'_cache'} );
        my $zonefile_obj         = $zone_file_objs_hr->{$target_zone};
        my $number_of_operations = scalar @$operations;
      OPERATION:
        for ( my $op_idx = 0; $op_idx < $number_of_operations; $op_idx++ ) {
            next if $operations_completed->[$op_idx];
            my $operation      = $operations->[$op_idx];
            my $results        = ( $zone_operations_hr->{$target_zone} ||= [] );
            my $op_record_type = $operation->{'type'};
            if ( !$zonefile_obj || !@{ $zonefile_obj->{'dnszone'} } ) {
                my $error = "The zone “$target_zone” is empty. Modification of “$name:$op_record_type” failed.";
                push @$results, [ 0, $error, $domain ];
                $self->_add_error($error);
                next OPERATION;
            }
            my $shortname = $zonefile_obj->_collapse_name($name);
            if ( $operation->{'operation'} eq 'add' ) {
                if (
                    $self->_op_has_cname_conflict(
                        'name'      => $name,
                        'operation' => $operation,
                        'results'   => $results,
                        'domain'    => $domain,
                    )
                ) {
                    $operations_completed->[$op_idx]++;
                    next OPERATION;
                }

                my $value = $template_obj->process( $operation->{'value'} );
                if ( !$value ) {
                    push @$results, [ 0, "Could not resolve empty value “$operation->{'value'}”", $domain ];
                    next OPERATION;
                }

                my $dnszone_entry = {
                    'name' => $name,
                    'type' => $op_record_type,
                    'ttl'  => $self->{'ttl'},
                };
                $zonefile_obj->set_zone_record_value( $dnszone_entry, $value );
                push @$results, [ 1, "ADD:$op_record_type\@$shortname:$value", $domain ];
                $zonefile_obj->add_record($dnszone_entry);
                $operations_completed->[$op_idx]++;
            }
            elsif ( $operation->{'operation'} ne 'delete' ) {
                push @$results, [ 0, "invalid operation '$operation->{'operation'}' requested for $domain", $domain ];
            }
        }
    }
    return;
}

sub _create_all_record_map_for_zones {
    my ($self) = @_;

    my $zone_file_objs_hr = $self->{'zone_file_objs_hr'};
    my %all_records;
    foreach my $zone ( keys %$zone_file_objs_hr ) {
        my $zonefile_obj      = $zone_file_objs_hr->{$zone};
        my $dnszone           = $zonefile_obj->{'dnszone'};
        my $number_of_records = scalar @$dnszone;
        for ( my $record_idx = 0; $record_idx < $number_of_records; $record_idx++ ) {
            my $name = $dnszone->[$record_idx]->{'name'} or next;
            my $type = $dnszone->[$record_idx]->{'type'} or next;
            $all_records{$name}{$type}++;
        }
    }
    $self->{'all_records_hr'} = \%all_records;
    return 1;
}

sub _create_zone_file_objs {
    my ( $self, $zones_ref ) = @_;
    local $SIG{'__WARN__'} = sub {
        $self->_add_error( $_[0] );
    };
    $self->{'zone_file_objs_hr'} = Cpanel::ZoneFile::Collection::create_zone_file_objs($zones_ref);
    delete @{$zones_ref}{ keys %$zones_ref };    #empty hash to reduce memory
    return 1;
}

sub _prune_operations_that_do_not_have_a_zone_to_operate_on {
    my ($self) = @_;

    my $dns_record_domains_hr    = ( $self->{'dns_record_domains_hr'} ||= {} );
    my $dns_record_operations_hr = $self->{'dns_record_operations_hr'};
    my @inoperable_records;
    foreach my $interested_record ( keys %$dns_record_operations_hr ) {
        if ( !$dns_record_operations_hr->{$interested_record}->[TARGET_ZONE] ) {
            $self->_add_error("There is no zone file on this system that can contain “$interested_record”.");
            push @inoperable_records, $interested_record;
            $dns_record_domains_hr->{ $dns_record_operations_hr->{$interested_record}->[DOMAIN] } = MISSING_ZONE;
        }
    }
    delete @{$dns_record_operations_hr}{@inoperable_records};
    return 1;
}

sub _load_zones_and_find_op_zone_targets {
    my ( $self, $pre_fetched_zones_hr ) = @_;

    my $dns_record_operations_hr = $self->{'dns_record_operations_hr'};
    my $dns_record_domains_hr    = ( $self->{'dns_record_domains_hr'} ||= {} );

    my %all_domains = map {
        chop;
        (
            $_ => undef,
        )
    } keys %$dns_record_operations_hr;

    my ( $domain_to_zone_map_hr, $zones_hr ) = Cpanel::Domain::Zone->new()->get_zones_for_domains( [ keys %all_domains ], $pre_fetched_zones_hr );

    foreach my $name ( keys %$dns_record_operations_hr ) {
        my $name_without_dot = $name;
        chop $name_without_dot;
        $dns_record_domains_hr->{ $dns_record_operations_hr->{$name}->[DOMAIN] } ||= HAS_ZONE;
        $dns_record_operations_hr->{$name}->[TARGET_ZONE]          = $domain_to_zone_map_hr->{$name_without_dot} || $domain_to_zone_map_hr->{ $dns_record_operations_hr->{$name}->[DOMAIN] };
        $dns_record_operations_hr->{$name}->[OPERATIONS_COMPLETED] = [ (0) x scalar @{ $dns_record_operations_hr->{$name}->[OPERATIONS] } ];
    }

    # Now we serialize each zone into an object so we can operate on it
    return $self->_create_zone_file_objs($zones_hr);
}

sub _match_any {
    my $text = shift;

    return 1 if !defined $_[0];    # match is not defined so match anything

    foreach my $match ( ref $_[0] ? @{ $_[0] } : @_ ) {
        if ( $text =~ /^\"?\Q$match\E/ ) {
            return 1;
        }
    }
    return 0;
}

1;
