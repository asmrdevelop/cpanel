package Cpanel::API::ServiceProxy;

# cpanel - Cpanel/API/ServiceProxy.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::API::ServiceProxy - UAPI functions for managing service proxying

=cut

use Cpanel::AdminBin::Call ();

=head1 API Functions

=head2 get_service_proxy_backends()

See L<https://go.cpanel.net/serviceproxy-get_service_proxy_backends>

=cut

sub get_service_proxy_backends ( $args, $result ) {

    $result->data( Cpanel::AdminBin::Call::call( 'Cpanel', 'service_proxy', 'GET_SERVICE_PROXY_BACKENDS' ) );

    return 1;
}

=head2 set_service_proxy_backends ( $args, $result )

See L<https://go.cpanel.net/serviceproxy-set_service_proxy_backends>

=cut

sub set_service_proxy_backends ( $args, $result ) {

    my @args_kv;

    if ( my $backend = $args->get('general') ) {
        push @args_kv, ( backend => $backend );
    }

    my @worker_types    = $args->get_multiple('service_group');
    my @worker_backends = $args->get_multiple('service_group_backend');

    if ( @worker_types != @worker_backends ) {
        die "Count of “service_group” (@worker_types) mismatches “service_group_backend” (@worker_backends)!\n";
    }

    if (@worker_types) {
        require Cpanel::AccountProxy::Storage;
        Cpanel::AccountProxy::Storage::validate_proxy_backend_types_or_die( \@worker_types );

        my %worker_backend;
        push @args_kv, ( worker => \%worker_backend );

        @worker_backend{@worker_types} = @worker_backends;
    }

    if (@args_kv) {
        Cpanel::AdminBin::Call::call( 'Cpanel', 'service_proxy', 'SET_SERVICE_PROXY_BACKENDS', @args_kv );
    }

    return 1;
}

=head2 unset_all_service_proxy_backends

See L<https://go.cpanel.net/serviceproxy-unset_all_service_proxy_backends>

=cut

sub unset_all_service_proxy_backends ( $args, $result ) {

    Cpanel::AdminBin::Call::call( 'Cpanel', 'service_proxy', 'UNSET_ALL_SERVICE_PROXY_BACKENDS' );

    return 1;
}

our %API = (
    get_service_proxy_backends       => undef,
    set_service_proxy_backends       => undef,
    unset_all_service_proxy_backends => undef,
);

1;
