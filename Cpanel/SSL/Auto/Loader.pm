package Cpanel::SSL::Auto::Loader;

# cpanel - Cpanel/SSL/Auto/Loader.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Loader

=head1 SYNOPSIS

    my $perl_module_name = Cpanel::SSL::Auto::Loader::get_and_load('cPanel');

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::Exception          ();
use Cpanel::LoadModule::Custom ();
use Cpanel::LoadModule::Utils  ();
use Cpanel::SSL::Auto::Utils   ();

#accessed from tests
our @_REQUIRED_METHODS = qw(
  renew_ssl_for_vhosts
);

=head2 get_and_load( MODULE_NAME )

Load a provider module by name, and return the module’s Perl namespace.

=cut

sub get_and_load {
    my ($provider) = @_;

    my $module = Cpanel::SSL::Auto::Utils::get_provider_namespace($provider);

    # Checking to see if the module is complete can be expensive
    # so lets only do it once per load
    if ( !Cpanel::LoadModule::Utils::module_is_loaded($module) ) {

        #This will load a custom module if one is available,
        #then fall back to cPanel-provided if not.
        Cpanel::LoadModule::Custom::load_perl_module($module);

        _verify_that_module_is_complete($module);
    }

    return $module;
}

#XXX - copied/pasted from Cpanel::Market
#overridden in tests
sub _verify_that_module_is_complete {
    my ($module) = @_;

    my @missing = grep { !$module->can($_) } @_REQUIRED_METHODS;

    return if !@missing;

    die Cpanel::Exception->create( 'The module “[_1]” is missing the required [numerate,_2,method,methods] [list_and_quoted,_3].', [ $module, scalar(@missing), \@missing ] );
}

1;
