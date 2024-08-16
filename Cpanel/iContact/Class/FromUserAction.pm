package Cpanel::iContact::Class::FromUserAction;

# cpanel - Cpanel/iContact/Class/FromUserAction.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This class adds the data for the "origin_info" template. It should be
# subclassed, not instantiated directly.
#----------------------------------------------------------------------

use strict;

use Try::Tiny;

use Cpanel::LoadModule ();
use Cpanel::Exception  ();

use parent qw(
  Cpanel::iContact::Class
);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        'origin',
        'source_ip_address',
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_required_args(),
        $self->SUPER::_template_args(),

        %{ $self->_origin_info_hr() },

        origin => $self->{'_opts'}{'origin'},
        domain => $self->{'_opts'}{'domain'},
    );
}

sub _origin_info_hr {
    my ($self) = @_;

    my $template_data_hr = {};

    Cpanel::LoadModule::load_perl_module('Cpanel::IP::Convert');
    Cpanel::LoadModule::load_perl_module('Cpanel::IP::Loopback');
    Cpanel::LoadModule::load_perl_module('Cpanel::IP::Utils');

    #normalize
    if ( length $self->{'_opts'}{'source_ip_address'} ) {
        my $ip = Cpanel::IP::Convert::binip_to_human_readable_ip( Cpanel::IP::Convert::ip2bin16( $self->{'_opts'}{'source_ip_address'} ) );
        $template_data_hr->{'ip_address'}           = $ip;
        $template_data_hr->{'ip_address_is_public'} = !Cpanel::IP::Utils::get_private_mask_bits_from_ip_address($ip);
        $template_data_hr->{'ip_address_is_public'} &&= !Cpanel::IP::Loopback::is_loopback($ip);

        if ( $template_data_hr->{'ip_address_is_public'} ) {

            #NOTE: Net::DNS::Resolver is quite a big module,
            #so it must ALWAYS be lazy-loaded, not use()d.
            Cpanel::LoadModule::load_perl_module('Net::DNS::Resolver');

            #Use default timeout (2 minutes as of version 1088)
            my $resolve = Net::DNS::Resolver->new()->query($ip);
            my @names;
            if ($resolve) {
                @names = map { $_->can('ptrdname') ? $_->ptrdname() : () } $resolve->answer();
            }

            $template_data_hr->{'reverse_dns_hostnames'} = \@names;

            try {
                no warnings;    #make Geo::IPfree silent;
                Cpanel::LoadModule::load_perl_module('Cpanel::GeoIPfree');
                my $geo = Cpanel::GeoIPfree->new();
                @{$template_data_hr}{qw(country_code country_name)} = $geo->LookUp($ip);
            }
            catch {
                $template_data_hr->{'country_lookup_error'} = Cpanel::Exception::get_string($_);
            };

            try {
                Cpanel::LoadModule::load_perl_module('Cpanel::Net::Whois::IP::Cached');
                my $objects = Cpanel::Net::Whois::IP::Cached->new()->lookup_address($ip);
                if ($objects) {
                    $template_data_hr->{'whois'} = $objects;
                }
            }
            catch {
                $template_data_hr->{'whois_lookup_error'} = Cpanel::Exception::get_string($_);
            };

        }

        # p0f query here if enabled
        if ($ip) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Services::Enabled');
            if ( Cpanel::Services::Enabled::is_enabled('p0f') ) {
                try {
                    Cpanel::LoadModule::load_perl_module('Cpanel::Net::P0f');
                    $template_data_hr->{'fingerprint'} = Cpanel::Net::P0f->new()->lookup_address($ip);
                }
                catch {
                    $template_data_hr->{'fingerprint_lookup_error'} = Cpanel::Exception::get_string($_);
                };
            }
        }
    }

    return $template_data_hr;
}

1;
