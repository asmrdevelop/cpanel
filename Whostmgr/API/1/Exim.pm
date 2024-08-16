package Whostmgr::API::1::Exim;

# cpanel - Whostmgr/API/1/Exim.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This module processes WHM API v1 sort/filter/chunk parameters and turns them
# into parameters that the backend functions will understand. This significantly
# improves performance over having the API layer do all of those operations
# itself.

use strict;
use warnings;

use Cpanel::DeliveryReporter::Utils ();
use Whostmgr::Exim                  ();
use Whostmgr::Exim::Config          ();
use Whostmgr::API::1::Data::Filter  ();
use Whostmgr::API::1::Data::Chunk   ();
use Whostmgr::API::1::Data::Utils   ();
use Whostmgr::API::1::Utils         ();

use constant NEEDS_ROLE => 'MailSend';

sub fetch_mail_queue {
    my ( $formref, $metadata, $api_args ) = @_;

    $formref = {%$formref};

    my @filter_funcs = Whostmgr::API::1::Data::Filter::get_filter_funcs( $api_args, $metadata );

    my @filters = Whostmgr::API::1::Data::Filter::get_filters($api_args);

    my $search_cr = @filter_funcs && sub {
        for (@filter_funcs) {
            return if !$_->( $_[0] );
        }

        return 1;
    };

    my ( $ok, $msg, $queue_ar, $before_filter ) = Whostmgr::Exim::fetch_mail_queue( $formref, $search_cr );

    Whostmgr::API::1::Data::Filter::mark_filters_done( $api_args, @filters );
    Whostmgr::API::1::Data::Filter::set_filtered_count( $api_args, $before_filter );

    @{$metadata}{ 'result', 'reason' } =
      $ok
      ? ( 1, 'OK' )
      : ( 0, $msg );

    return { records => $queue_ar };
}

sub validate_current_installed_exim_config {
    my ( $formref, $metadata ) = @_;

    my ( $ok, $msg, $content ) = Whostmgr::Exim::Config::validate_current_installed_exim_config();

    @{$metadata}{ 'result', 'reason' } =
      $ok
      ? ( 1, $msg || 'OK' )
      : ( 0, $msg );

    return { message => $content };
}

sub exim_configuration_check {
    my ( $formref, $metadata ) = @_;

    my ( $ok, $msg, $content ) = Whostmgr::Exim::Config::configuration_check();

    @{$metadata}{ 'result', 'reason' } =
      $ok
      ? ( 1, $msg || 'OK' )
      : ( 0, $msg );

    return { message => $content };
}

sub validate_exim_configuration_syntax {
    my ( $formref, $metadata ) = @_;

    my $check = Whostmgr::Exim::validate_exim_configuration_syntax($formref);

    @{$metadata}{ 'result', 'reason' } =
      $check->{status}
      ? ( 1, 'OK' )
      : ( 0, $check->{error_msg} || $metadata->{reason} );

    if ( exists $check->{rawout} ) {
        $metadata->{'output'}->{'raw'} = $check->{rawout};
        delete $check->{rawout};
    }
    delete $check->{status};
    delete $check->{error_msg};

    return $check;
}

sub remove_in_progress_exim_config_edit {
    my ( $formref, $metadata ) = @_;

    my ( $ok, $msg ) = Whostmgr::Exim::Config::remove_in_progress_exim_config_edit($formref);

    @{$metadata}{ 'result', 'reason' } =
      $ok
      ? ( 1, $msg || 'OK' )
      : ( 0, $msg );

    return undef;
}

sub search {
    my ( $formref, $metadata, $api_args ) = @_;

    my $filter  = $api_args->{'filter'};
    my @filters = Whostmgr::API::1::Data::Filter::get_filters( $filter, $metadata );

    if (@filters) {
        Cpanel::DeliveryReporter::Utils::convert_filters_for_query( $formref, \@filters );
        Whostmgr::API::1::Data::Filter::mark_filters_done( $filter, @filters );
    }

    require Whostmgr::EmailTrack;
    return _do_func( \&Whostmgr::EmailTrack::search, $formref, $metadata, $api_args );
}

sub stats {
    require Whostmgr::EmailTrack;
    return _do_func( \&Whostmgr::EmailTrack::stats, @_ );
}

sub user_stats {
    my ( $formref, $metadata, $api_args ) = @_;

    my $filter  = $api_args->{filter};
    my @filters = Whostmgr::API::1::Data::Filter::get_filters( $filter, $metadata );
    Whostmgr::API::1::Data::Filter::mark_filters_done( $filter, @filters ) if @filters;

    # Necessary or else the filtering doesn’t actually work.
    local $formref->{'filters'} = \@filters;

    require Whostmgr::EmailTrack;
    return _do_func( \&Whostmgr::EmailTrack::user_stats, $formref, $metadata, $api_args );
}

sub get_unique_sender_recipient_count_per_user {

    my ( $args, $metadata ) = @_;

    require Cpanel::EximStats::SpamCheck;
    my $results = Cpanel::EximStats::SpamCheck::get_unique_sender_recipient_count_per_user(%$args);

    @$metadata{qw(result reason)} = ( 1, 'OK' );

    return { 'payload' => [ map { { user => $_, unique_sender_recipient_count => $results->{$_} } } keys %$results ] };
}

sub get_unique_recipient_count_per_sender_for_user {

    my ( $args, $metadata ) = @_;

    require Cpanel::EximStats::SpamCheck;
    my $results = Cpanel::EximStats::SpamCheck::get_unique_recipient_count_per_sender_for_user(%$args);

    @$metadata{qw(result reason)} = ( 1, 'OK' );

    return { 'payload' => [ map { { sender => $_, unique_recipient_count => $results->{$_} } } keys %$results ] };
}

sub block_incoming_email_from_country {
    my ( $args, $metadata ) = @_;
    return _modify_block_incoming_email_from_country( 'block', $args, $metadata );
}

sub unblock_incoming_email_from_country {
    my ( $args, $metadata ) = @_;
    return _modify_block_incoming_email_from_country( 'unblock', $args, $metadata );
}

sub list_blocked_incoming_email_countries {
    my ( $args, $metadata ) = @_;
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    require Whostmgr::Exim::BlockedCountries;
    return { countries => [ map { { country_code => $_ } } @{ Whostmgr::Exim::BlockedCountries::list_blocked_incoming_email_countries() } ] };
}

sub _modify_block_incoming_email_from_country {
    my ( $action, $args, $metadata ) = @_;

    my @country_codes = Whostmgr::API::1::Utils::get_length_required_arguments( $args, 'country_code' );

    require Whostmgr::Exim::BlockedCountries;
    my $result = Whostmgr::Exim::BlockedCountries::modify_blocked_incoming_email_countries( $action, \@country_codes );
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { updated => $result ? 1 : 0 };
}

sub block_incoming_email_from_domain {
    my ( $args, $metadata ) = @_;
    return _modify_block_incoming_email_from_domain( 'block', $args, $metadata );
}

sub unblock_incoming_email_from_domain {
    my ( $args, $metadata ) = @_;
    return _modify_block_incoming_email_from_domain( 'unblock', $args, $metadata );
}

sub list_blocked_incoming_email_domains {
    my ( $args, $metadata ) = @_;
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    require Whostmgr::Exim::BlockedDomains;
    return { domains => [ map { { domain => $_ } } @{ Whostmgr::Exim::BlockedDomains::list_blocked_incoming_email_domains() } ] };
}

sub set_manual_mx_redirects {
    my ( $args, $metadata ) = @_;

    my $domains_hr = Whostmgr::API::1::Utils::map_length_required_multiple_to_key_values( $args, 'domain', 'mx_host' );

    require Cpanel::Exim::ManualMX;
    my $existing = Cpanel::Exim::ManualMX::set_manual_mx_redirects($domains_hr);

    $metadata->set_ok();

    return { payload => $existing };
}

sub unset_manual_mx_redirects {
    my ( $args, $metadata ) = @_;

    my @domains = Whostmgr::API::1::Utils::get_length_required_arguments( $args, 'domain' );

    require Cpanel::Exim::ManualMX;
    my $removed = Cpanel::Exim::ManualMX::unset_manual_mx_redirects( \@domains );

    $metadata->set_ok();

    return { payload => $removed };
}

sub _modify_block_incoming_email_from_domain {
    my ( $action, $args, $metadata ) = @_;

    my @domains = Whostmgr::API::1::Utils::get_length_required_arguments( $args, 'domain' );

    require Whostmgr::Exim::BlockedDomains;
    my $result = Whostmgr::Exim::BlockedDomains::modify_blocked_incoming_email_domains( $action, \@domains );
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { updated => $result ? 1 : 0 };
}

sub _do_func {

    my ( $func, $formref, $metadata, $api_args ) = @_;

    _handle_sort( $formref, $metadata, $api_args );

    my $chunk_post = _handle_chunk( $formref, $metadata, $api_args );

    my ( $ok, $msg, $records, $total_after_filter, $overflowed ) = $func->($formref);

    if ( 'HASH' eq ref $records ) {
        $records = [$records];
    }

    @{$metadata}{ 'result', 'reason', 'overflowed' } = $ok ? ( 1, 'OK', $overflowed ? 1 : 0 ) : ( 0, $msg );

    if ($ok) {
        if ($chunk_post) {
            $chunk_post->( $records, $total_after_filter );
        }

        return { records => $records };
    }

    return;
}

sub _handle_sort {
    my ( $formref, $metadata, $api_args ) = @_;

    my $sort = $api_args->{'sort'};
    if ( $sort && $sort->{'enable'} ) {
        my $key;
        for my $cur_key ( sort keys %$sort ) {
            if ( Whostmgr::API::1::Data::Utils::id_is_valid($cur_key) ) {
                $key = $cur_key;
                last;
            }
        }
        return if !defined $key;

        $formref->{'sort'} = $sort->{$key}{'field'};
        $formref->{'dir'}  = $sort->{$key}{'reverse'} ? 'desc' : 'asc';

        $sort->{$key}->{'__done'} = 1;    # Tell the api that the data is already sorted by this key
    }

    return;
}

sub _handle_chunk {
    my ( $formref, $metadata, $api_args ) = @_;

    my $chunk = $api_args->{'chunk'};
    my $post_cr;
    if ( $chunk && $chunk->{'enable'} ) {
        my $size  = $chunk->{'size'} || $Whostmgr::API::1::Data::Chunk::DEFAULT_CHUNK_SIZE;
        my $index = 0;
        if ( $chunk->{'start'} ) {
            $index = $chunk->{'start'} - 1;
        }
        elsif ( $chunk->{'select'} ) {
            $index = $size * ( $chunk->{'select'} - 1 );
        }

        @{$formref}{ 'startIndex', 'results' } = ( $index, $size );

        if ( $chunk->{'verbose'} ) {
            $post_cr = sub {
                my ( $records, $count ) = @_;
                $metadata->{'chunk'} = {
                    start   => $formref->{'startIndex'} + 1,
                    size    => $formref->{'results'},
                    records => $count || 0,

                    #TODO
                    #current,
                    #chunks,
                };
            };
        }
    }

    ##Tell the API that the data is already chunked/paginated.
    $metadata->{'__chunked'} = 1;

    return $post_cr || ();
}

1;
