package Cpanel::GreyList::Handler;

# cpanel - Cpanel/GreyList/Handler.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::GreyList::Config ();

use Cpanel::IP::Convert ();

my $singleton;

sub new {
    my ($class) = @_;
    return $singleton if ( ref $singleton and $singleton->isa('Cpanel::GreyList::Handler') );

    $singleton = bless {}, $class;

    return $singleton;
}

sub should_defer {
    my ( $self, $logger, $data_ar ) = @_;
    $data_ar = [] if !$data_ar || 'ARRAY' ne ref $data_ar;

    if ( scalar @{$data_ar} != 3 ) {
        $logger->info( "Invalid request for 'should_defer' OP. Request data: ['" . join( ',', @{$data_ar} ) . "']" );
        return;
    }

    $_ =~ s/\x{01}/ /g for @$data_ar;

    my ( $sender_ip, $from_addr, $to_addr ) = @{$data_ar};
    $data_ar->[0] = Cpanel::IP::Convert::ip2bin16($sender_ip);
    my ($receiving_domain) = $to_addr =~ m/^.+\@(.*)$/;

    my $db = $self->_get_db_connection_singleton();
    local $db->{'dbh'}{AutoCommit} = 0;

    if ( my $reason = _should_defer( $db, $data_ar->[0], $receiving_domain ) ) {
        $logger->info("Request:- OP: ['should_defer'], Sender IP: ['$sender_ip'], From Address: ['$from_addr'], To Address: ['$to_addr']. Reply:- ['no ($reason)']");
        return 'no';
    }

    my $reply;
    if ( my $record_id = $db->has_existing_deferred_entry($data_ar) ) {
        if ( $db->has_initial_block_expired($record_id) ) {
            $db->increment_accepted_counter($record_id);
            $reply = 'no';
        }
        else {
            $db->increment_deferred_counter($record_id);
            $reply = 'yes';
        }
    }
    else {
        my $config = Cpanel::GreyList::Config::loadconfig();
        $db->insert_new_deferred_entry( $data_ar, $config );
        $reply = 'yes';
    }
    $db->{'dbh'}->commit;

    $logger->info("Request:- OP: ['should_defer'], Sender IP: ['$sender_ip'], From Address: ['$from_addr'], To Address: ['$to_addr']. Reply:- ['$reply']");
    return $reply;
}

sub get_deferred_list {
    my ( $self, $logger, $data_ar, $send_raw_response ) = @_;
    $data_ar = [] if !$data_ar || 'ARRAY' ne ref $data_ar;

    my $filtered_for_ip = 0;
    if ( $data_ar->[5] && eval { require Cpanel::Validate::IP; Cpanel::Validate::IP::is_valid_ip( $data_ar->[5] ); } ) {
        $filtered_for_ip = 1;
        $data_ar->[5] = Cpanel::IP::Convert::ip2bin16( $data_ar->[5] );
    }

    # Note: $data_ar is sanitized and updated in $db->get_deferred_list().
    my $db = $self->_get_db_connection_singleton();
    my ( $data, $total_rows ) = $db->get_deferred_list($data_ar);
    foreach my $entry ( @{$data} ) {
        $entry->{'sender_ip'} = Cpanel::IP::Convert::binip_to_human_readable_ip( delete $entry->{'sender_ip'} );
    }

    my $reply = {
        'data'       => $data,
        'total_rows' => $total_rows,
    };

    my ( $limit, $offset, $order_by, $order, $is_filter, $filter ) = @{$data_ar};
    $filter = Cpanel::IP::Convert::binip_to_human_readable_ip($filter) if $filtered_for_ip;
    $logger->info( "Request:- OP: ['get_deferred_list'], Limit: ['$limit'], Offset: ['$offset'], Order By: ['$order_by'], Order: ['$order'], Filtered: ['$is_filter'], Filter: ['$filter']. Returned:- ['" . scalar @{$data} . " record(s)']" );

    return $reply if $send_raw_response;

    return _json($reply);
}

sub create_trusted_host {
    my ( $self, $logger, $data_ar, $send_raw_response ) = @_;
    $data_ar = [] if !$data_ar || 'ARRAY' ne ref $data_ar;

    if ( !scalar @{$data_ar} || scalar @{$data_ar} > 2 ) {
        $logger->info( "Invalid request for 'create_trusted_host' OP. Request data: ['" . join( ',', @{$data_ar} ) . "']" );
        return;
    }

    my ( $start_address, $end_address ) = _get_ip_range( $data_ar->[0] );

    if ( my $reply = $self->_get_db_connection_singleton()->create_trusted_host( [ $start_address, $end_address, $data_ar->[1] ] ) ) {
        my $start_human_readable_address = Cpanel::IP::Convert::binip_to_human_readable_ip( delete $reply->{'host_ip_start'} );
        my $end_human_readable_address   = Cpanel::IP::Convert::binip_to_human_readable_ip( delete $reply->{'host_ip_end'} );

        if ( $start_human_readable_address eq $end_human_readable_address ) {
            $reply->{'host_ip'} = $start_human_readable_address;
        }
        else {
            $reply->{'host_ip'} = "$start_human_readable_address-$end_human_readable_address";
        }

        return $reply if $send_raw_response;

        return _json($reply);
    }

    return;
}

sub read_trusted_hosts {
    my ( $self, $logger, $send_raw_response ) = @_;
    $send_raw_response = 0 if !$send_raw_response || 'ARRAY' eq ref $send_raw_response && !scalar @{$send_raw_response};

    my $data = $self->_get_db_connection_singleton()->read_trusted_hosts();
    foreach my $entry ( @{$data} ) {
        my $start_human_readable_address = Cpanel::IP::Convert::binip_to_human_readable_ip( delete $entry->{'host_ip_start'} );
        my $end_human_readable_address   = Cpanel::IP::Convert::binip_to_human_readable_ip( delete $entry->{'host_ip_end'} );

        if ( $start_human_readable_address eq $end_human_readable_address ) {
            $entry->{'host_ip'} = $start_human_readable_address;
        }
        else {
            $entry->{'host_ip'} = "$start_human_readable_address-$end_human_readable_address";
        }
    }
    return $data if $send_raw_response;
    return _json($data);
}

sub delete_trusted_host {
    my ( $self, $logger, $data_ar ) = @_;
    $data_ar = [] if !$data_ar || 'ARRAY' ne ref $data_ar;

    if ( scalar @{$data_ar} != 1 ) {
        $logger->info( "Invalid request for 'delete_trusted_host' OP. Request data: ['" . join( ',', @{$data_ar} ) . "']" );
        return;
    }

    my ( $start_address, $end_address ) = _get_ip_range( $data_ar->[0] );
    if ( $self->_get_db_connection_singleton()->delete_trusted_host( [ $start_address, $end_address ] ) ) {
        return 1;
    }

    return;
}

sub verify_trusted_hosts {
    my ( $self, $logger, $data_hr, $send_raw_response ) = @_;
    $data_hr = {} if !$data_hr || 'HASH' ne ref $data_hr;

    if ( !scalar %{$data_hr} ) {
        $logger->info("Invalid request for 'verify_trusted_hosts' OP. Request data: ['']");
        return;
    }

    foreach my $cidr ( keys %{$data_hr} ) {
        my ( $start_address, $end_address ) = _get_ip_range($cidr);

        delete $data_hr->{$cidr};
        my $start_human_readable_address = Cpanel::IP::Convert::binip_to_human_readable_ip($start_address);
        my $end_human_readable_address   = Cpanel::IP::Convert::binip_to_human_readable_ip($end_address);

        my $new_key = ( $start_human_readable_address eq $end_human_readable_address ) ? $start_human_readable_address : "$start_human_readable_address-$end_human_readable_address";
        if ( $self->_get_db_connection_singleton()->is_trusted_range( [ $start_address, $end_address ] ) ) {
            $data_hr->{$new_key} = 1;
        }
        else {
            $data_hr->{$new_key} = 0;
        }
    }

    return $data_hr if $send_raw_response;

    return _json($data_hr);
}

sub purge_old_records {
    my ( $self, $logger ) = @_;

    my $db              = $self->_get_db_connection_singleton();
    my $records_removed = $db->purge_old_records();
    $logger->info("Purged old records from DB. Record(s) removed: $records_removed");
    return 1;
}

sub is_greylisting_enabled {
    my ( $self, $domain ) = @_;
    return $self->_get_db_connection_singleton()->is_greylisting_enabled($domain);
}

sub disable_opt_out_for_domains {
    my ( $self, $domains ) = @_;
    $domains = [] if !$domains || 'ARRAY' ne ref $domains;

    return if !scalar @{$domains};
    return $self->_get_db_connection_singleton()->disable_opt_out_for_domains($domains);
}

sub enable_opt_out_for_domains {
    my ( $self, $domains ) = @_;
    $domains = [] if !$domains || 'ARRAY' ne ref $domains;

    return if !scalar @{$domains};
    return $self->_get_db_connection_singleton()->enable_opt_out_for_domains($domains);
}

sub add_entries_for_common_mail_provider {
    my ( $self, $logger, $data_ar ) = @_;
    $data_ar = [] if !$data_ar || 'ARRAY' ne ref $data_ar;

    if ( !scalar @{$data_ar} || scalar @{$data_ar} > 2 ) {
        $logger->info( "Invalid request for 'add_entries_for_common_mail_provider' OP. Request data: ['" . join( ',', @{$data_ar} ) . "']" );
        return;
    }
    my ( $provider, $ips_ar ) = @{$data_ar};
    return if 'ARRAY' ne ref $ips_ar && scalar @{$ips_ar};

    my @bin_ips;
    foreach my $ip ( @{$ips_ar} ) {
        my ( $start_address, $end_address ) = _get_ip_range($ip);
        push @bin_ips, [ $start_address, $end_address ];
    }

    my $db = $self->_get_db_connection_singleton();
    local $db->{'dbh'}{AutoCommit} = 0;
    $db->add_entries_for_common_mail_provider( $provider, \@bin_ips );
    $db->{'dbh'}->commit;
    return 1;
}

sub delete_entries_for_common_mail_provider {
    my ( $self, $logger, $data_ar ) = @_;
    $data_ar = [] if !$data_ar || 'ARRAY' ne ref $data_ar;

    if ( !scalar @{$data_ar} || scalar @{$data_ar} > 1 ) {
        $logger->info( "Invalid request for 'delete_entries_for_common_mail_provider' OP. Request data: ['" . join( ',', @{$data_ar} ) . "']" );
        return;
    }

    return $self->_get_db_connection_singleton()->delete_entries_for_common_mail_provider( $data_ar->[0] );
}

sub trust_entries_for_common_mail_provider {
    my ( $self, $provider ) = @_;
    return if not length $provider;

    return $self->_get_db_connection_singleton()->trust_entries_for_common_mail_provider($provider);
}

sub untrust_entries_for_common_mail_provider {
    my ( $self, $provider ) = @_;
    return if not length $provider;

    return $self->_get_db_connection_singleton()->untrust_entries_for_common_mail_provider($provider);
}

sub list_entries_for_common_mail_provider {
    my ( $self, $provider ) = @_;
    return if not length $provider;

    my $data = $self->_get_db_connection_singleton()->list_entries_for_common_mail_provider($provider);
    foreach my $entry ( @{$data} ) {
        my $start_human_readable_address = Cpanel::IP::Convert::binip_to_human_readable_ip( delete $entry->{'host_ip_start'} );
        my $end_human_readable_address   = Cpanel::IP::Convert::binip_to_human_readable_ip( delete $entry->{'host_ip_end'} );

        if ( $start_human_readable_address eq $end_human_readable_address ) {
            $entry->{'host_ip'} = $start_human_readable_address;
        }
        else {
            $entry->{'host_ip'} = "$start_human_readable_address-$end_human_readable_address";
        }
    }
    return $data;
}

sub get_common_mail_providers {
    my $self = shift;
    return $self->_get_db_connection_singleton()->get_common_mail_providers();
}

sub add_mail_provider {
    my ( $self, $provider, $display_name, $last_updated ) = @_;
    return if not( length $provider && length $display_name );

    return $self->_get_db_connection_singleton()->add_mail_provider( $provider, $display_name, $last_updated );
}

sub remove_mail_provider {
    my ( $self, $provider ) = @_;
    return if not length $provider;

    return $self->_get_db_connection_singleton()->remove_mail_provider($provider);
}

sub rename_mail_provider {
    my ( $self, $old_provider, $new_provider ) = @_;
    return unless length $old_provider && length $new_provider;

    return $self->_get_db_connection_singleton()->rename_mail_provider( $old_provider, $new_provider );
}

sub bump_last_updated_for_mail_provider {
    my ( $self, $provider, $last_updated ) = @_;
    return if not length $provider;

    return $self->_get_db_connection_singleton()->bump_last_updated_for_mail_provider( $provider, $last_updated );
}

sub update_display_name_for_mail_provider {
    my ( $self, $provider, $display_name ) = @_;
    return unless length $provider && length $display_name;

    return $self->_get_db_connection_singleton()->update_display_name_for_mail_provider( $provider, $display_name );
}

sub _get_db_connection_singleton {
    my ($self) = @_;

    return ( $self->{'_db_connection'} ||= _init_db_connection() );
}

sub _json {
    my $to_json = shift;

    my $json;
    eval {
        require Cpanel::JSON;
        $json = Cpanel::JSON::Dump($to_json);
    };
    return $json;
}

sub _init_db_connection {
    my $opts = shift;

    require Cpanel::GreyList::DB;
    return Cpanel::GreyList::DB->new( Cpanel::GreyList::Config::get_sqlite_db(), $opts );
}

sub _get_ip_range {
    my $ip = shift;

    my ( $start_address, $end_address ) = Cpanel::IP::Convert::ip_range_to_start_end_address($ip);

    if ( !length $start_address || !length $end_address ) {
        require Cpanel::Exception;
        die Cpanel::Exception->create( "Invalid IP address or range: [_1]", [$ip] );
    }

    return ( $start_address, $end_address );
}

sub _should_defer {
    my ( $db, $ip_bin, $receiving_domain ) = @_;

    # We do not defer the email in these situations:
    # If the mail is from a trusted host
    return 'Trusted Host' if $db->is_trusted_host($ip_bin);

    # If its from a trusted common mail provider,
    return 'Trusted Common Mail Provider' if $db->is_trusted_common_mail_provider($ip_bin);

    # If the receiving domain has opt'ed out of greylisting,
    return 'Receiving domain has opted-out' if !$db->is_greylisting_enabled($receiving_domain);

    return;
}

1;
