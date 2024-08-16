
# cpanel - Cpanel/ImagePrep/Task/exim_srs_secret.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::exim_srs_secret;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::Exim::Config ();

use Try::Tiny;

=head1 NAME

Cpanel::ImagePrep::Task::exim_srs_secret - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
Pre- / post-snapshot actions for Exim. Clears and regenerates the Exim
SRS secret (if present) in the Exim srs_config file.
EOF
}

sub _type { return 'non-repair only' }

sub _pre ($self) {

    # always remove the srs_secret file (no need to restore it)
    $self->common->_unlink($Cpanel::Exim::Config::SRS_SECRET_FILE);

    my $srs_conf_file = $Cpanel::Exim::Config::SRS_CONFIG_FILE;

    if ( !$self->common->_exists($srs_conf_file) ) {
        $self->loginfo('pre: Exim SRS configuration does not exist.');
        return $self->PRE_POST_NOT_APPLICABLE;
    }

    $self->common->_unlink($srs_conf_file);

    # leave the configuration empty so exim can see it on boot
    $self->common->_touch($srs_conf_file);

    $self->loginfo('Cleared Exim SRS secret');

    return $self->PRE_POST_OK;
}

sub _post ($self) {

    if ( !$self->common->_exists($Cpanel::Exim::Config::SRS_CONFIG_FILE) ) {
        $self->loginfo('post: Exim SRS configuration does not exist.');
        return $self->PRE_POST_NOT_APPLICABLE;
    }

    my $error = '';
    my $ok    = try {
        Cpanel::Exim::Config->new()->_setup_srs_config_file();
    }
    catch {
        $error = $_;
        0;
    };

    if ( !$ok ) {
        $self->loginfo("Fail to generate Exim SRS configuration file: $error");
        return $self->PRE_POST_NOT_APPLICABLE;
    }

    $self->loginfo('Regenerated Exim SRS secret');
    $self->need_restart('exim');

    return $self->PRE_POST_OK;
}

1;
