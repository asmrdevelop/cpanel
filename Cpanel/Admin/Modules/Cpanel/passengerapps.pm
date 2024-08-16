#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/passengerapps.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::passengerapps;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Exception  ();
use Cpanel::LoadModule ();

sub _actions {
    return qw(
      REGISTER_APPLICATION
      LIST_APPLICATIONS
      EDIT_APPLICATION
      UNREGISTER_APPLICATION
      ENABLE_APPLICATION
      DISABLE_APPLICATION
    );
}

sub _demo_actions {
    return qw(
      LIST_APPLICATIONS
    );
}

sub REGISTER_APPLICATION {
    my ( $self, $config_hr ) = @_;
    $self->cpuser_has_feature_or_die('passengerapps');

    require Cpanel::Config::userdata::PassengerApps;
    my $obj = Cpanel::Config::userdata::PassengerApps->new( { 'user' => scalar $self->get_caller_username() } );

    my $userdata = $self->_get_caller_cpuser_data();

    my $max_apps = $userdata->{'MAXPASSENGERAPPS'};

    if ( length $max_apps ) {
        $max_apps = $max_apps =~ m/unlimited/i ? 'unlimited' : int $max_apps;
    }
    else {
        require Cpanel::Config::CpUser::Defaults;
        $max_apps = {@Cpanel::Config::CpUser::Defaults::DEFAULTS_KV}->{'MAXPASSENGERAPPS'};
    }

    die Cpanel::Exception->create( 'You reached your account’s allotment of applications, [numf,_1].', [$max_apps] )
      if $max_apps ne 'unlimited' && $max_apps <= scalar keys %{ $obj->list_applications() };

    # Parameter validation may throw an exception collection
    $self->whitelist_exception('Cpanel::Exception::Collection');

    my $data = $obj->register_application($config_hr);

    if ( $data->{'enabled'} ) {
        $obj->generate_apache_conf( $data->{'name'} );

        Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::ApRestart::BgSafe');
        Cpanel::HttpUtils::ApRestart::BgSafe::restart();
    }
    $obj->save_changes_to_disk();

    _do_nginx( $self->get_caller_username() );

    return $data;
}

sub LIST_APPLICATIONS {
    my ($self) = @_;
    $self->cpuser_has_feature_or_die('passengerapps');

    my $user = $self->get_caller_username();
    require Cpanel::Config::userdata::PassengerApps;
    my $obj = Cpanel::Config::userdata::PassengerApps->new( { 'user' => $user, 'read_only' => 1 } );

    return $obj->list_applications();
}

sub EDIT_APPLICATION {
    my ( $self, $config_hr ) = @_;
    $self->cpuser_has_feature_or_die('passengerapps');

    # Parameter validation may throw an exception collection
    $self->whitelist_exception('Cpanel::Exception::Collection');

    my $user = $self->get_caller_username();
    require Cpanel::Config::userdata::PassengerApps;
    my $obj  = Cpanel::Config::userdata::PassengerApps->new( { 'user' => $user } );
    my $data = $obj->edit_application($config_hr);

    my $previous = delete $data->{'previous_app_data'};

    my $needs_restart = 0;
    if ( !$previous->{'name'} || !$previous->{'domain'} || $previous->{'name'} ne $data->{'name'} || $previous->{'domain'} ne $data->{'domain'} ) {
        $obj->remove_apache_conf( $previous->{'name'}, $previous->{'domain'} );
        $needs_restart++;
    }

    if ( $previous->{'enabled'} && !$data->{'enabled'} ) {
        $obj->remove_apache_conf( $data->{'name'}, $data->{'domain'} );
        $needs_restart++;
    }
    elsif ( $data->{'enabled'} ) {
        $obj->generate_apache_conf( $data->{'name'} );
        $needs_restart++;
    }

    $obj->save_changes_to_disk();

    if ($needs_restart) {
        Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::ApRestart::BgSafe');
        Cpanel::HttpUtils::ApRestart::BgSafe::restart();
    }

    _do_nginx($user);

    return $data;
}

sub UNREGISTER_APPLICATION {
    my ( $self, $name ) = @_;
    $self->cpuser_has_feature_or_die('passengerapps');

    my $user = $self->get_caller_username();
    require Cpanel::Config::userdata::PassengerApps;
    my $obj = Cpanel::Config::userdata::PassengerApps->new( { 'user' => $user } );

    if ( my $app_data = $obj->unregister_application($name) ) {
        $obj->remove_apache_conf( $app_data->{'name'}, $app_data->{'domain'} );

        Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::ApRestart::BgSafe');
        Cpanel::HttpUtils::ApRestart::BgSafe::restart();

        $obj->save_changes_to_disk();

        _do_nginx($user);
    }

    return 1;
}

sub DISABLE_APPLICATION {
    my ( $self, $name ) = @_;
    $self->cpuser_has_feature_or_die('passengerapps');

    my $user = $self->get_caller_username();
    require Cpanel::Config::userdata::PassengerApps;
    my $obj = Cpanel::Config::userdata::PassengerApps->new( { 'user' => $user } );

    if ( my $app_data = $obj->disable_application($name) ) {
        $obj->remove_apache_conf( $app_data->{'name'}, $app_data->{'domain'} );

        Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::ApRestart::BgSafe');
        Cpanel::HttpUtils::ApRestart::BgSafe::restart();

        $obj->save_changes_to_disk();

        _do_nginx($user);
    }

    return 1;
}

sub ENABLE_APPLICATION {
    my ( $self, $name ) = @_;
    $self->cpuser_has_feature_or_die('passengerapps');

    my $user = $self->get_caller_username();
    require Cpanel::Config::userdata::PassengerApps;
    my $obj = Cpanel::Config::userdata::PassengerApps->new( { 'user' => $user } );

    if ( my $app_data = $obj->enable_application($name) ) {
        $obj->generate_apache_conf( $app_data->{'name'} );

        Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::ApRestart::BgSafe');
        Cpanel::HttpUtils::ApRestart::BgSafe::restart();

        $obj->save_changes_to_disk();

        _do_nginx($user);
    }

    return 1;
}

sub _do_nginx {
    my ($user) = @_;

    my $nginx_script = "/usr/local/cpanel/scripts/ea-nginx";
    if ( -x $nginx_script ) {
        require Cpanel::SafeRun::Object;
        eval {
            Cpanel::SafeRun::Object->new_or_die(
                program => $nginx_script,
                args    => [ config => $user ],
            );
        };
        warn $@ if $@;    # will get logged
    }

    return;
}

1;
