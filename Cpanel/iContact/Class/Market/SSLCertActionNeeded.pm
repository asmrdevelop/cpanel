package Cpanel::iContact::Class::Market::SSLCertActionNeeded;

# cpanel - Cpanel/iContact/Class/Market/SSLCertActionNeeded.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::Market::SSLCertActionNeeded - iContact module for ssl certification actions.

=head1 DESCRIPTION

When an action is required to complete an SSL certificate order (usually an OV or EV),
this notification is sent to the user with instructions on what to do.

=cut

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel::SSL::Utils ();
use Cpanel::Market     ();

my @sale_properties = (

    'provider',
    'order_id',
    'order_item_id',
    'product_id',
);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @sale_properties,

        'username',
        'vhost_name',
    );
}

sub _template_args {
    my ($self) = @_;

    my $username = $self->{'_opts'}{'username'};

    my $vh_name = $self->{'_opts'}{'vhost_name'};

    my $action_urls = $self->{'_opts'}{'action_urls'};

    my $csr = $self->{'_opts'}{'csr'};

    if ( !$csr ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'csr' ] );
    }

    my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_csr_text($csr);

    die $parse if !$ok;

    #Don’t filter by “vhost_is_ssl” here for testing purposes.

    my $vendor_ns = Cpanel::Market::get_and_load_module_for_provider( $self->{'_opts'}{'provider'} );
    my ($product_name) = map { $_->{'product_id'} eq $self->{'_opts'}{'product_id'} ? $_->{'display_name'} : () } $vendor_ns->get_products_list();

    return (
        $self->SUPER::_template_args(),
        ( map { $_ => $self->{'_opts'}{$_} } @sale_properties ),
        provider_display_name => Cpanel::Market::get_provider_display_name( $self->{'_opts'}{'provider'} ),
        product_name          => $product_name,
        vhost_name            => $self->{'_opts'}{'vhost_name'},
        csr_domains           => $parse->{'domains'},
        action_urls           => $action_urls,
    );
}

1;
