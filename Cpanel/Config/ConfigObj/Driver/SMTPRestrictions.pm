package Cpanel::Config::ConfigObj::Driver::SMTPRestrictions;

# cpanel - Cpanel/Config/ConfigObj/Driver/SMTPRestrictions.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::ConfigObj::Driver::SMTPRestrictions::META ();
*VERSION = \$Cpanel::Config::ConfigObj::Driver::SMTPRestrictions::META::VERSION;

use Cpanel::Config::ConfigObj ();
use Cpanel::LoadModule        ();

# This driver implements v1 spec
use parent qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

sub init {
    my ( $class, $software_obj ) = @_;

    my $smtp_defaults = {
        'settings'      => {},
        'thirdparty_ns' => "",
        'meta'          => {},
    };
    my $self = $class->SUPER::base( $smtp_defaults, $software_obj );

    return $self;
}

# Provides enable action for SMTP Restrictions feature
sub enable {
    my ($self) = @_;

    my $interface = $self->interface();
    Cpanel::LoadModule::load_perl_module('Whostmgr::TweakSettings');

    if ( !Whostmgr::TweakSettings::set_value( 'Main', 'smtpmailgidonly', 1 ) ) {
        $interface->set_error( Cpanel::Config::ConfigObj::E_ERROR, "Could not enable SMTP Restrictions setting.\n" );
        return;
    }

    my $meta_obj     = $self->meta();
    my $feature_name = $meta_obj->name('short');

    # schedule a task - hupcpsrvd
    $interface->schedule('hupcpsrvd');
    $interface->set_notice("$feature_name has been enabled.\n");
    return 1;
}

# Provides disable action for SMTP Restrictions feature
sub disable {
    my ($self) = @_;
    my $interface = $self->interface();

    Cpanel::LoadModule::load_perl_module('Whostmgr::TweakSettings');

    # make sure and pass the force as this is happening due to an explicit action
    if ( !Whostmgr::TweakSettings::set_value( 'Main', 'smtpmailgidonly', 0, 1 ) ) {
        $interface->set_error( Cpanel::Config::ConfigObj::E_ERROR, "Could not disable SMTP Restrictions setting.\n" );
        return;
    }

    my $meta_obj     = $self->meta();
    my $feature_name = $meta_obj->name('short');

    # schedule a task - hupcpsrvd
    $interface->schedule('hupcpsrvd');
    $interface->set_notice("$feature_name has been disabled.\n");
    return 1;
}

# Provides SMTP Restrictions feature information.
sub info {
    my ($self)   = @_;
    my $meta_obj = $self->meta();
    my $abstract = $meta_obj->abstract();

    return $abstract;
}

# 2015-03-13: We recommend people enable SMTP Restrictions
sub check {
    return 1;
}

sub status {
    my $current_val = Whostmgr::TweakSettings::get_value( 'Main', 'smtpmailgidonly' ) ? 1 : 0;
    return $current_val;
}

1;
