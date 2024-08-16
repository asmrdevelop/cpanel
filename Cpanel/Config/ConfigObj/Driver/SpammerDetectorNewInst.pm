package Cpanel::Config::ConfigObj::Driver::SpammerDetectorNewInst;

# cpanel - Cpanel/Config/ConfigObj/Driver/SpammerDetectorNewInst.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::ConfigObj::Driver::SpammerDetectorNewInst::META ();
*VERSION = \$Cpanel::Config::ConfigObj::Driver::SpammerDetectorNewInst::META::VERSION;

use Cpanel::Config::ConfigObj         ();
use Cpanel::Exception                 ();
use Cpanel::FeatureShowcase           ();
use Cpanel::iContact::EventImportance ();
use Cpanel::LoadModule                ();

# This driver implements v1 spec
use parent qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

my $icontact_app   = "Mail";
my $icontact_event = "SpammersDetected";

=head1 NAME

Cpanel::Config::ConfigObj::Driver::SpammerDetectorNewInst

=head1 DESCRIPTION

Feature Showcase driver for SpammerDetectorNewInst

=cut

=head1 SYNOPSIS

Boilerplate subroutines for the feature showcase. This is an auto-enabled FS.

=cut

=head1 Subroutines

=head2 init

Initializes the feature showcase object.

=cut

sub init {
    my ( $class, $software_obj ) = @_;

    my $defaults = {
        'settings'      => {},
        'thirdparty_ns' => "",
    };
    my $self = $class->SUPER::base( $defaults, $software_obj );

    return $self;
}

=head2 info

returns the info text.

=cut

sub info {
    my ($self) = @_;
    return $self->meta()->abstract();
}

=head2 enable

returns 1 after enabling the feature.

=cut

sub enable {
    my ($self) = @_;
    return $self->_configFeature();
}

=head2 disable

returns 1; this is an auto-enabled feature.

=cut

sub disable {
    return 1;
}

=head2 check

returns 1 if the notification is enabled

=cut

sub check {
    my ($self) = @_;
    my $current_setting = 0;

    my $importance = Cpanel::iContact::EventImportance->new()->get_event_importance( $icontact_app, $icontact_event );
    $current_setting = 1 if $importance > 0;

    return $current_setting;
}

=head2 _configFeature

this local routine does the heavy lifting of changing the state of the notification

=cut

sub _configFeature {
    my ( $self, ) = @_;

    my $interface = $self->interface();
    my $meta_obj  = $self->meta();

    my $importance = 'High';

    my $err;
    eval {
        Cpanel::LoadModule::load_perl_module('Cpanel::iContact::EventImportance::Writer');

        my $importance_number = $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{$importance};
        my $imp_writer        = Cpanel::iContact::EventImportance::Writer->new();
        $imp_writer->set_event_importance( $icontact_app, $icontact_event, $importance_number );
        $imp_writer->save_and_close();
    };
    if ($@) {
        $err = $@;
    }

    if ($err) {
        $interface->set_error( Cpanel::Config::ConfigObj::E_ERROR, "The notification for ${icontact_app}::${icontact_event} could not be auto-enabled because of an error: " . Cpanel::Exception::get_string($err), __LINE__ );
        return undef;
    }

    # We don't want the SpammerDetect driver turning up when they start WHM!
    # Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/activate/features/spammer_detector');

    my $manager = Cpanel::FeatureShowcase->new( { 'version' => '1' } );
    $manager->write_feature_status_file( 'spammer_detector', $Cpanel::FeatureShowcase::SOURCE_GUI );

    $interface->set_notice("${icontact_app}::${icontact_event} has been enabled.");

    return 1;
}

1;
