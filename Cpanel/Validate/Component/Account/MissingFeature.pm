package Cpanel::Validate::Component::Account::MissingFeature;

# cpanel - Cpanel/Validate/Component/Account/MissingFeature.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw ( Cpanel::Validate::Component );

use Cpanel::Exception              ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Features::Check        ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( ownership_user feature_name ));
    $self->add_optional_arguments(qw( feature_list ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ( $username, $feature_name, $feature_list ) = @{$self}{ $self->get_validation_arguments() };

    if ( !$feature_list ) {
        my $cpuser_data = Cpanel::Config::LoadCpUserFile::loadcpuserfile($username);
        $feature_list = $cpuser_data->{'FEATURELIST'};
    }

    die Cpanel::Exception::create( 'FeatureNotEnabled', [ feature_name => $feature_name ] ) if !Cpanel::Features::Check::check_feature_for_user( $username, $feature_name, $feature_list );

    return;
}

1;
