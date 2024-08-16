package Cpanel::Security::Advisor::Assessors::SSH;

# cpanel - Cpanel/Security/Advisor/Assessors/SSH.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Whostmgr::Services::SSH::Config ();
use Cpanel::PackMan                 ();

use base 'Cpanel::Security::Advisor::Assessors';

sub version {
    return '1.02';
}

sub generate_advice {
    my ($self) = @_;
    $self->_check_for_ssh_settings;
    $self->_check_for_ssh_version;

    return 1;
}

sub _check_for_ssh_settings {
    my ($self) = @_;

    my $scfg        = Whostmgr::Services::SSH::Config->new();
    my $sshd_config = $scfg->get_config();
    if ( $scfg->get_config('PasswordAuthentication') =~ m/yes/i || $scfg->get_config('ChallengeResponseAuthentication') =~ m/yes/i ) {
        $self->add_bad_advice(
            'key'        => 'SSH_password_authentication_enabled',
            'text'       => $self->_lh->maketext('SSH password authentication is enabled.'),
            'suggestion' => $self->_lh->maketext(
                'Disable SSH password authentication in the “[output,url,_1,SSH Password Authorization Tweak,_2,_3]” area',
                $self->base_path('scripts2/tweaksshauth'),
                'target',
                '_blank'
            ),
        );
    }
    else {
        $self->add_good_advice(
            'key'  => 'SSH_password_authentication_disabled',
            'text' => $self->_lh->maketext('SSH password authentication is disabled.'),
        );

    }

    if ( !$scfg->get_config('PermitRootLogin') || $scfg->get_config('PermitRootLogin') =~ m/yes/i ) {
        $self->add_bad_advice(
            'key'        => 'SSH_direct_root_login_permitted',
            'text'       => $self->_lh->maketext('SSH direct root logins are permitted.'),
            'suggestion' => $self->_lh->maketext(
                'Manually edit /etc/ssh/sshd_config and change PermitRootLogin to “without-password” or “no”, then restart SSH in the “[output,url,_1,Restart SSH,_2,_3]” area',
                $self->base_path('scripts/ressshd'),
                'target',
                '_blank'
            ),
        );
    }
    else {
        $self->add_good_advice(
            'key'  => 'SSH_direct_root_logins_disabled',
            'text' => $self->_lh->maketext('SSH direct root logins are disabled.'),
        );

    }

    return 1;

}

sub _check_for_ssh_version {
    my ($self) = @_;

    my $pkm     = Cpanel::PackMan->instance;
    my $pkginfo = $pkm->pkg_hr('openssh-server');

    my $current_sshversion = $pkginfo->{'version_installed'};
    my $latest_sshversion  = $pkginfo->{'version_latest'};

    if ( length $current_sshversion && length $latest_sshversion ) {
        if ( $current_sshversion lt $latest_sshversion ) {
            $self->add_bad_advice(
                'key'        => 'SSH_version_outdated',
                'text'       => $self->_lh->maketext('Current SSH version is out of date.'),
                'suggestion' => $self->_lh->maketext(
                    'Update current system software in the “[output,url,_1,Update System Software,_2,_3]” area',
                    $self->base_path('scripts/dialog?dialog=updatesrvsoftware'),
                    'target',
                    '_blank'
                ),
            );
        }
        else {
            $self->add_good_advice(
                'key'  => 'SSH_is_current',
                'text' => $self->_lh->maketext( 'Current SSH version is up to date: [_1]', $current_sshversion )
            );
        }
    }
    else {
        $self->add_warn_advice(
            'key'        => 'SSH_can_not_determine_version',
            'text'       => $self->_lh->maketext('Unable to determine SSH version'),
            'suggestion' => $self->_lh->maketext('Ensure that the package manager is working on your system.')
        );
    }

    return 1;

}

1;
