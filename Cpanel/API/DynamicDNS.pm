package Cpanel::API::DynamicDNS;

# cpanel - Cpanel/API/DynamicDNS.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::API::DynamicDNS

=cut

#----------------------------------------------------------------------

use Cpanel::AdminBin::Call ();

#----------------------------------------------------------------------

=head1 API FUNCTIONS

=head2 list()

See L<https://go.cpanel.net/dynamicdns-list>.

=cut

sub list ( $, $result ) {
    my $entries_hr = Cpanel::AdminBin::Call::call(
        'Cpanel', 'webcalls', 'GET_ENTRIES',
    );

    my @response;

    for my $id ( keys %$entries_hr ) {
        my $entry_hr = $entries_hr->{$id};

        # Accommodate future expansion
        next if $entry_hr->{'type'} ne 'DynamicDNS';

        my $last_run_times = $entry_hr->{'last_run_times'};

        my $created_time     = $entry_hr->{'created_time'};
        my $last_update_time = $entry_hr->{'last_update_time'};

        require Cpanel::Time::ISO;

        $_ &&= Cpanel::Time::ISO::iso2unix($_)
          for (
            @$last_run_times,
            $created_time,
            $last_update_time,
          );

        my %output = (
            %{ $entry_hr->{'data'} }{ 'domain', 'description' },

            created_time     => $created_time,
            last_update_time => $last_update_time,
            last_run_times   => $last_run_times,

            id => $id,
        );

        push @response, \%output;
    }

    _augment_list_with_ips(@response);

    $result->data( \@response );

    return 1;
}

sub _augment_list_with_ips (@response) {
    my @domains = map { $_->{'domain'} } @response;

    my @results;

    while ( my @batch = splice @domains, 0, 100 ) {
        push @results, Cpanel::AdminBin::Call::call(
            'Cpanel', 'zone', 'ASK_LOCAL',
            map { [ $_, 'A', 'AAAA' ] } @batch,
        );
    }

    require Cpanel::DNS::Rdata;

    for my $item_hr (@response) {
        my ( @v4, @v6 );

        for my $result_ar ( @{ shift @results } ) {
            if ( $result_ar->[0] eq 'A' ) {
                push @v4, $result_ar->[1];
            }
            else {
                push @v6, $result_ar->[1];
            }
        }

        Cpanel::DNS::Rdata::parse_a( \@v4 ) if @v4;

        if (@v6) {
            Cpanel::DNS::Rdata::parse_aaaa( \@v6 );

            require Cpanel::IPv6::RFC5952;
            for my $addr (@v6) {
                $addr = Cpanel::IPv6::RFC5952::convert($addr);
            }
        }

        @{$item_hr}{ 'ipv4', 'ipv6' } = ( \@v4, \@v6 );
    }

    return;
}

=head2 create()

See L<https://go.cpanel.net/dynamicdns-create>.

=cut

sub create ( $args, $result ) {
    my $domain = $args->get_length_required('domain');
    my $descr  = $args->get('description') || "";

    my $create_data = {
        domain      => $domain,
        description => $descr,
    };

    require Cpanel::WebCalls::Type::DynamicDNS;

    Cpanel::WebCalls::Type::DynamicDNS->normalize_entry_data(
        $Cpanel::user,
        $create_data,
    );

    my $why_bad = Cpanel::WebCalls::Type::DynamicDNS->why_entry_data_invalid(
        $Cpanel::user,
        $create_data,
    );

    if ($why_bad) {
        $result->raw_error($why_bad);
        return 0;
    }

    my ( $id, $created ) = Cpanel::AdminBin::Call::call(
        'Cpanel', 'webcalls', 'CREATE',
        'DynamicDNS',
        $create_data,
    );

    require Cpanel::Time::ISO;
    $created = Cpanel::Time::ISO::iso2unix($created);

    $result->data( { id => $id, created_time => $created } );

    return 1;
}

=head2 set_description()

See L<https://go.cpanel.net/dynamicdns-set_description>.

=cut

sub set_description ( $args, $result ) {

    my $id    = $args->get_length_required('id');
    my $descr = $args->get_length_required('description');

    return 0 if !_validate_id_or_falsy( $id, $result );

    require Cpanel::WebCalls::Datastore::ReadAsUser;
    my $entries_hr = Cpanel::WebCalls::Datastore::ReadAsUser::read_all();

    my $entry_hr = $entries_hr->{$id} if $entries_hr->{$id} && $entries_hr->{$id}{'type'} eq 'DynamicDNS';

    if ( !$entry_hr ) {
        $result->raw_error("Nonexistent “id”: $id");
        return 0;
    }

    my $update_data = { description => $descr };

    require Cpanel::WebCalls::Type::DynamicDNS;
    my $why_bad = Cpanel::WebCalls::Type::DynamicDNS->why_update_data_invalid(
        $Cpanel::user,
        $update_data,
    );

    if ($why_bad) {
        $result->raw_error($why_bad);
        return 0;
    }

    Cpanel::AdminBin::Call::call(
        'Cpanel', 'webcalls', 'UPDATE_DATA',
        $id,
        $entry_hr->{'data'},
        $update_data,
    );

    return 1;
}

sub _validate_id_or_falsy ( $id, $result ) {
    require Cpanel::WebCalls::ID;
    if ( !Cpanel::WebCalls::ID::is_valid($id) ) {
        $result->raw_error("Invalid “id”: $id");
        return 0;
    }

    return 1;
}

=head2 recreate()

See L<https://go.cpanel.net/dynamicdns-recreate>.

=cut

sub recreate ( $args, $result ) {
    my $id = $args->get_length_required('id');

    return 0 if !_validate_id_or_falsy( $id, $result );

    my $new_id = Cpanel::AdminBin::Call::call(
        'Cpanel', 'webcalls', 'RECREATE', $id,
    );

    $result->data( { id => $new_id } );

    return 1;
}

=head2 delete()

See L<https://go.cpanel.net/dynamicdns-delete>.

=cut

sub delete ( $args, $result ) {
    my $id = $args->get_length_required('id');

    return 0 if !_validate_id_or_falsy( $id, $result );

    my $deleted = Cpanel::AdminBin::Call::call(
        'Cpanel', 'webcalls', 'DELETE', $id,
    );

    $result->data( { deleted => $deleted } );

    return 1;
}

our %API = (
    '_needs_role'    => 'DNS',
    '_needs_feature' => 'dynamicdns',
);

1;
