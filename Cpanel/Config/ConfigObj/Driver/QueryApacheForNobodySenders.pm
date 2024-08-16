package Cpanel::Config::ConfigObj::Driver::QueryApacheForNobodySenders;

# cpanel - Cpanel/Config/ConfigObj/Driver/QueryApacheForNobodySenders.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::ConfigObj::Driver::QueryApacheForNobodySenders::META ();
*VERSION = \$Cpanel::Config::ConfigObj::Driver::QueryApacheForNobodySenders::META::VERSION;

use Cpanel::LoadModule ();

# This driver implements v1 spec
use parent qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

sub init {
    my ( $class, $software_obj ) = @_;

    my $defaults = {
        'settings'      => {},
        'thirdparty_ns' => "",
    };

    my $self = $class->SUPER::base( $defaults, $software_obj );

    return $self;
}

sub enable {
    my ($self) = @_;

    return $self->_update_setting(1);
}

sub disable {
    my ($self) = @_;
    return $self->_update_setting(0);
}

sub info {
    my ($self) = @_;
    return $self->meta()->abstract();
}

sub check {
    my ($self) = @_;

    return 1;
}

sub status {
    return -e '/var/cpanel/config/email/query_apache_for_nobody_senders' ? 1 : 0;
}

sub _update_setting {
    my ( $self, $new_setting ) = @_;

    $new_setting ||= 0;

    Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
    Cpanel::LoadModule::load_perl_module('Cpanel::Transaction::File::LoadConfig');

    my $config = Cpanel::Transaction::File::LoadConfig->new( 'path' => '/etc/exim.conf.localopts', 'delimiter' => '=', 'permissions' => 0644, 'allow_undef_values' => 1 );
    $config->set_entry( 'query_apache_for_nobody_senders' => $new_setting );

    #TODO: publish errors to the caller
    () = $config->save_and_close( do_sort => 1 );

    Cpanel::SafeDir::MK::safemkdir( '/var/cpanel/config/email', 0755 );
    if ($new_setting) {
        Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::TouchFile');
        Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/config/email/query_apache_for_nobody_senders');
    }
    else {
        unlink('/var/cpanel/config/email/query_apache_for_nobody_senders');
    }

    my $interface = $self->interface();
    my $action    = ( $new_setting == 1 ) ? 'enabled' : 'disabled';

    $interface->set_notice("Query Apache For Nobody Senders has been $action.");

    return 1;
}

1;
