package Cpanel::Async::RemoteAPI;

# cpanel - Cpanel/Async/RemoteAPI.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::RemoteAPI

=head1 DESCRIPTION

This module implements a base class for making asynchronous cPanel & WHM
API calls via HTTP to a specific remote host.

It extends L<Cpanel::RemoteAPI::Base>. Use of L<AnyEvent> is assumed.

=head1 EXTRA CONSTRUCTOR PARAMETERS

The following may be given as named parameters to the
constructors:

=over

=item * C<pool_size> - Optional, indicates the max # of API connections to
keep open. The bigger this number, the more concurrent requests you can
send before this module starts throttling requests, and the more file
descriptors you’ll hold open. (Default: 10)

=back

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::RemoteAPI::Base';

use cPanel::APIClient ();

use Net::Curl::Promiser::AnyEvent ();

use Cpanel::Async::Throttler       ();
use Cpanel::Promise::Interruptible ();

use constant _DEFAULT_POOL_SIZE => 10;

sub _NEW_OPTS ($) {
    return ('pool_size');
}

#----------------------------------------------------------------------

sub _throttle_p ( $self, $todo_cr ) {
    $self->{'_throttler'} ||= do {
        my $pool_size = $self->{'_api_args'}{'pool_size'} || _DEFAULT_POOL_SIZE;
        Cpanel::Async::Throttler->new($pool_size);
    };

    return $self->{'_throttler'}->add($todo_cr);
}

sub _already_connected ($self) {
    return !!$self->{'_api'};
}

sub _request ( $self, $fn, @args ) {

    my ( $canceled_before_started, $pending );

    my $api = $self->_api_obj();

    my $throttled = $self->_throttle_p(
        sub {
            my $promise;

            if ( !$canceled_before_started ) {
                $pending = $api->$fn(@args);
                $promise = $pending->promise();
            }

            return $promise;
        }
    );

    return Cpanel::Promise::Interruptible->new(
        $throttled,
        sub {
            if ($pending) {
                $api->cancel($pending);
            }
            else {
                $canceled_before_started = 1;
            }
        },
    );
}

sub _api_obj ($self) {
    return $self->{'_api'} ||= do {
        my $promiser = Net::Curl::Promiser::AnyEvent->new();

        # Ideally this is where we’d set CURLMOPT_MAX_TOTAL_CONNECTIONS,
        # but CentOS’s curls are quite old (7.29 in CentOS 7), which means
        # that feature is unavailable.

        cPanel::APIClient->create(
            service => $self->_CPANEL_APICLIENT_SERVICE(),

            transport => [
                'NetCurlPromiser',

                promiser => $promiser,
                hostname => $self->get_hostname(),

                $self->_get_transport_args(),
            ],

            credentials => {
                username => $self->get_username(),

                $self->_get_authn_credentials(),
            },
        );
    };
}

sub _get_transport_args ($self) {
    my @transport_args;

    my $ssl_mode = $self->{'_api_args'}{'ssl_verify_mode'};
    if ( defined $ssl_mode && !$ssl_mode ) {
        push @transport_args, ( tls_verification => 'off' );
    }

    return @transport_args;
}

sub _get_authn_credentials ($self) {
    if ( my $pw = $self->{'_api_args'}{'pass'} ) {
        return ( password => $pw );
    }
    elsif ( my $ahash = $self->{'_api_args'}{'accesshash'} ) {
        return ( api_token => $ahash );
    }

    die "No credentials!";
}

1;
