package Cpanel::Plugins::Promotions::koality;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use Moo;
use cPstrict;

use Cpanel::Plugins::RestApiClient ();
use Cpanel::License::CompanyID     ();
use Cpanel::JSON                   ();

with 'Cpanel::Plugins::Cache';

=head1 MODULE

C<Cpanel::Plugins::Promotions::koality>

=head1 DESCRIPTION

C<Cpanel::Plugins::Promotions::koality> is a class that provides methods for managing koality promotions

=cut

has 'use_stage' => (
    is      => 'ro',
    default => sub {
        return -f '/var/cpanel/use_koality_stage';
    },
);

has 'koality_stage_url' => (
    is      => 'ro',
    default => 'https://api.stage.koalityengine.com/kapi/v1/',
);

has 'koality_prod_url' => (
    is      => 'ro',
    default => 'https://api.cluster1.koalityengine.com/v1/',
);

has 'init_cache' => (
    is      => 'ro',
    default => sub ($self) {
        $self->setup_cache( ['can_show_promotions'] );
    },
);

has 'api' => (
    is      => 'ro',
    lazy    => 1,
    default => sub ($self) {
        my $api = Cpanel::Plugins::RestApiClient->new();
        $api->base_url( $self->use_stage ? $self->koality_stage_url() : $self->koality_prod_url() );
        return $api;
    },
);

has 'company_id' => (
    is      => 'ro',
    default => sub {
        return Cpanel::License::CompanyID::get_company_id();
    }
);

=head1 METHODS

=head2 C<can_show_promotions>

Returns whether or not the current server can show plugin upsell promotions to users.

=cut

sub can_show_promotions ($self) {
    return 0 if !$self->company_id();

    $self->api->endpoint( "marketplace/features/paid/company/" . $self->company_id() );

    # For some reason it needs an arbitrary payload set.
    $self->api->payload( {} );
    my $response = $self->api->run();

    $response = Cpanel::JSON::Load($response);
    return $response->{data}{enabled} ? 1 : 0;
}

1;
