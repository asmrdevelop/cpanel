package Cpanel::iContact::Class::Market::SSLWebInstall;

# cpanel - Cpanel/iContact/Class/Market/SSLWebInstall.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#FIXME: Move this to a different namespace since it now has things like
#order ID, provider, and certificate ID.

use strict;
use warnings;

use List::MoreUtils qw(uniq);

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel::Apache::TLS                     ();
use Cpanel::Market                          ();
use Cpanel::SSL::Objects::Certificate::File ();
use Cpanel::WebVhosts                       ();
use Cpanel::WildcardDomain                  ();

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

    my $cert_path = Cpanel::Apache::TLS->get_certificates_path($vh_name);

    my $cert_obj = Cpanel::SSL::Objects::Certificate::File->new( path => $cert_path );
    my $cert_pem = $cert_obj->text();

    my @vhost_data = Cpanel::WebVhosts::list_ssl_capable_domains($username);

    #Don’t filter by “vhost_is_ssl” here for testing purposes.
    my @vh_domains = uniq sort map { $_->{'vhost_name'} eq $vh_name ? $_->{'domain'} : () } @vhost_data;

    my @cert_domains = @{ $cert_obj->domains() };

    for my $vd (@vh_domains) {
        my $covered = grep { Cpanel::WildcardDomain::wildcard_domains_match( $vd, $_ ) } @cert_domains;

        $vd = {
            name    => $vd,
            covered => $covered ? 1 : 0,
        };
    }

    # Sort by covered first, and by name second
    @vh_domains = sort { $b->{'covered'} <=> $a->{'covered'} || $a->{'name'} cmp $b->{'name'} } @vh_domains;

    my $vendor_ns = Cpanel::Market::get_and_load_module_for_provider( $self->{'_opts'}{'provider'} );
    my ($product_name) = map { $_->{'product_id'} eq $self->{'_opts'}{'product_id'} ? $_->{'display_name'} : () } $vendor_ns->get_products_list();

    return (
        $self->SUPER::_template_args(),

        ( map { $_ => $self->{'_opts'}{$_} } @sale_properties ),

        certificate_pem => $cert_pem,

        provider_display_name => Cpanel::Market::get_provider_display_name( $self->{'_opts'}{'provider'} ),

        product_name => $product_name,

        certificate   => $cert_obj,
        vhost_name    => $self->{'_opts'}{'vhost_name'},
        vhost_domains => \@vh_domains,
    );
}

1;
