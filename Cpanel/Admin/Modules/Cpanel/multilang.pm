
# cpanel - Cpanel/Admin/Modules/Cpanel/multilang.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::multilang;

use strict;
use warnings;

use Cpanel::Exception ();

use parent qw( Cpanel::Admin::Base );

sub _actions {
    return qw/SET_VHOST_LANG_PACKAGE UPDATE_VHOST_CPANEL/;
}

sub SET_VHOST_LANG_PACKAGE {
    my ( $self, $vhost, $langtype, $package ) = @_;

    $self->cpuser_has_feature_or_die('multiphp');

    my $user = $self->get_caller_username();

    die Cpanel::Exception::create( 'MissingParameter', '[quant,_1,parameter is,parameters are] required for “[_2]”: [list_and,_3]', [ 3, 'SET_VHOST_LANG_PACKAGE', [qw( vhost langtype package )] ] ) if !( defined $vhost && defined $langtype && defined $package );

    _bail_if_user_does_not_own_vhost( $user, $vhost );

    require Cpanel::ProgLang;
    my $lang = Cpanel::ProgLang->new( type => $langtype );

    if ( ( $package ne 'inherit' ) && ( !grep { $_ eq $package } @{ $lang->get_installed_packages() } ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” package is not available for the “[_2]” language.", [ $package, $langtype ] );
    }

    require Cpanel::WebServer;
    my $ws = Cpanel::WebServer->new();
    $ws->set_vhost_lang_package( user => $user, vhost => $vhost, package => $package, lang => $lang );

    return 1;
}

sub UPDATE_VHOST_CPANEL {
    my ( $self, $version, @vhosts ) = @_;

    $self->cpuser_has_feature_or_die('multiphp');

    my $results_ref = [];

    require Cpanel::PHP::Config;
    my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_domains( \@vhosts );
    my $user           = $self->get_caller_username();

    require Cpanel::PHP::Vhosts;

    foreach my $vhost (@vhosts) {
        _bail_if_user_does_not_own_vhost( $user, $vhost );    # TODO/YAGNI? check them all first and then start operating on them (i.e. two loops) for now: not sure if something was done or not? well garbage in garbage out, soooooo don't send in garbage!

        eval { Cpanel::PHP::Vhosts::php_set_vhost_versions_as_root( $version, $vhost, $php_config_ref, 0 ); };
        if ($@) {
            my $ref = { 'vhost' => $vhost, 'status' => 0, 'msg' => Cpanel::Exception::get_string_no_id($@) };
            push( @{$results_ref}, $ref );
        }
        else {
            my $ref = { 'vhost' => $vhost, 'status' => 1, 'msg' => 'Success' };
            push( @{$results_ref}, $ref );
        }
    }

    # Only rebuild configs and restart services once all requested vhosts have been processed
    Cpanel::PHP::Vhosts::rebuild_configs_and_restart($php_config_ref);

    return $results_ref;
}

sub _bail_if_user_does_not_own_vhost {
    my ( $user, $vhost ) = @_;
    require Cpanel::AcctUtils::DomainOwner::Tiny;
    my $owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($vhost);

    if ( $owner ne $user ) {
        die Cpanel::Exception::create( "DomainOwnership", "The account “[_1]” does not own the domain “[_2]”.", [ $user, $vhost ] );
    }

    return 1;
}

1;

__END__

=head1 NAME

bin::admin::Cpanel::multilang

=head1 SYNOPSIS

  use Cpanel::AdminBin::Call ()
  my $adminbin_return = Cpanel::AdminBin::Call::call( 'Cpanel', 'multilang', 'SET_VHOST_LANG_PACKAGE', $vhost, $lang, $package );

=head1 DESCRIPTION

bin::admin::Cpanel::multilang is a modulino created to be callable
Cpanel::AdminBin.

The primary purose of this module is to provide a way for a customer
to modify their multi-language settings via the UAPI.

=head1 SUBROUTINES

=over 4

=item SET_VHOST_LANG_PACKAGE

A Cpanel::AdminBin compatible wrapper allowing users to update a provided
vhost with the specified version of a language they wish to assign to it.

=item UPDATE_VHOST_CPANEL

A Cpanel::AdminBin compatible wrapper allowing cpanel users to update
vhost and fpm values.

=back

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved.
