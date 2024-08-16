
# cpanel - Cpanel/ImagePrep/Task/cpanelid.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::cpanelid;

use cPstrict;
use Cpanel::Security::Authn::Config        ();
use Cpanel::Security::Authn::OpenIdConnect ();

use parent 'Cpanel::ImagePrep::Task';

use constant {
    OPENID_SERVICE_NAME  => 'cpaneld',
    OPENID_PROVIDER_NAME => 'cpanelid',
};

=head1 NAME

Cpanel::ImagePrep::Task::cpanelid - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
Remove and regenerate the cPanelID configuration.
EOF
}

sub _type { return 'non-repair only' }

sub _pre ($self) {

    if ( !$self->common->_exists( _CPANELID() ) ) {
        $self->loginfo('cPanelID configuration does not exist.');
        return $self->PRE_POST_NOT_APPLICABLE;
    }

    if ( $self->common->_unlink( _CPANELID() ) ) {
        $self->loginfo('Removed the cPanelID configuration.');
        return $self->PRE_POST_OK;
    }

    $self->loginfo('Failed to remove the cPanelID configuration.');
    return $self->PRE_POST_FAILED;
}

sub _post ($self) {

    my $provider = Cpanel::Security::Authn::OpenIdConnect::get_openid_provider( OPENID_SERVICE_NAME(), OPENID_PROVIDER_NAME() );
    $provider->set_client_configuration( { 'client_id' => 'auto', 'client_secret' => 'auto' } );

    $self->loginfo('Regenerated the cPanelID configuration.');

    return $self->PRE_POST_OK;
}

sub _CPANELID {
    return $Cpanel::Security::Authn::Config::OPEN_ID_CLIENT_CONFIG_DIR . '/' . OPENID_PROVIDER_NAME();
}

1;
