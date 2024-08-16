package Cpanel::ApacheConf::DCV;

# cpanel - Cpanel/ApacheConf/DCV.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::ApacheConf::DCV

=head1 SYNOPSIS

    #Patterns to match the paths as reported from any installed cPanel Market
    #and AutoSSL provider modules. These can be inserted into
    #mod_rewrite directives as needed.
    my @paths = Cpanel::ApacheConf::DCV::get_patterns();

=cut

use Cpanel::Context                        ();
use Cpanel::SSL::DCV::Constants            ();
use Cpanel::SSL::DCV::Ballot169::Constants ();

sub get_patterns {
    Cpanel::Context::must_be_list();

    my %uniq;
    @uniq{ Cpanel::SSL::DCV::Constants::REQUEST_URI_DCV_PATH() } = ();
    @uniq{ _ballot_169_dcvs() }                                  = ();
    @uniq{ _autossl_provider_dcvs() }                            = ();
    @uniq{ _cpmarket_provider_dcvs() }                           = ();

    return keys %uniq;
}

#mocked in tests
sub _ballot_169_dcvs {
    return Cpanel::SSL::DCV::Ballot169::Constants::REQUEST_URI_DCV_PATH();
}

#mocked in tests
sub _autossl_provider_dcvs {
    my @dcvs;

    require Cpanel::SSL::Auto::Utils;
    require Cpanel::SSL::Auto::Loader;

    for my $p ( Cpanel::SSL::Auto::Utils::get_provider_module_names() ) {
        my $perl_ns = Cpanel::SSL::Auto::Loader::get_and_load($p);

        my $ex = $perl_ns->REQUEST_URI_DCV_PATH();

        push @dcvs, $ex if $ex;
    }

    return @dcvs;
}

#mocked in tests
sub _cpmarket_provider_dcvs {
    my @dcvs;

    require Cpanel::Market::Tiny;

    for my $p ( Cpanel::Market::Tiny::get_provider_names() ) {
        my $perl_ns;

        #Treat the cP provider as “special”.
        if ( $p eq 'cPStore' ) {
            require Cpanel::Market::Provider::cPStore::Constants;    # PPI USE OK - it gets used
            $perl_ns = 'Cpanel::Market::Provider::cPStore::Constants';
        }
        else {
            require Cpanel::Market;
            $perl_ns = Cpanel::Market::get_and_load_module_for_provider($p);
        }

        next if !$perl_ns->can('REQUEST_URI_DCV_PATH');
        my $ex = $perl_ns->REQUEST_URI_DCV_PATH();
        next if !$ex;

        push @dcvs, $ex;
    }

    return @dcvs;
}

1;
