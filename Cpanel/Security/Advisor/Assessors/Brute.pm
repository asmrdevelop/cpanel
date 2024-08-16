package Cpanel::Security::Advisor::Assessors::Brute;

# cpanel - Cpanel/Security/Advisor/Assessors/Brute.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Config::Hulk ();
use Cpanel::PsParser     ();
use Cpanel::LoadFile     ();
use Whostmgr::Imunify360 ();

use base 'Cpanel::Security::Advisor::Assessors';

sub generate_advice {
    my ($self) = @_;
    $self->_check_for_brute_force_protection();

    return 1;
}

sub _check_for_brute_force_protection {
    my ($self) = @_;

    my $security_advisor_obj = $self->{'security_advisor_obj'};

    # Hulk enabled?
    if ( Cpanel::Config::Hulk::is_enabled() ) {
        $security_advisor_obj->add_advice(
            {
                'key'  => 'Brute_protection_enabled',
                'type' => $Cpanel::Security::Advisor::ADVISE_GOOD,
                'text' => $self->_lh->maketext('cPHulk Brute Force Protection is enabled.'),
            }
        );
        return 1;
    }

    # CSF Present?
    if ( -x "/usr/sbin/csf" ) {
        if ( -e "/etc/csf/csf.disable" ) {
            $security_advisor_obj->add_advice(
                {
                    'key'        => 'Brute_csf_disabled',
                    'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                    'text'       => $self->_lh->maketext('[asis,CSF] is installed, but appears to be disabled.'),
                    'suggestion' => $self->_lh->maketext(
                        'Click “Firewall Enable” in the “[output,url,_1,_2,_3,_4]” area. Alternately, run “[asis,csf -e]” from the command line.',
                        $self->base_path('cgi/configserver/csf.cgi'),
                        'ConfigServer Security & Firewall',
                        'target',
                        '_blank'
                    ),
                }
            );
            return 1;
        }

        if ( lfd_is_running() ) {
            $security_advisor_obj->add_advice(
                {
                    'key'  => 'Brute_csf_installed_lfd_running',
                    'type' => $Cpanel::Security::Advisor::ADVISE_GOOD,
                    'text' => $self->_lh->maketext('[asis,CSF] is installed, and [asis,LFD] is running.'),
                }
            );
            return 1;
        }

        # The cPanel UI is there. Tell them how they can re-start lfd there.
        if ( -e "/usr/local/cpanel/whostmgr/docroot/cgi/configserver/csf" ) {
            $security_advisor_obj->add_advice(
                {
                    'key'        => 'Brute_csf_installed_lfd_not_running_1',
                    'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                    'text'       => $self->_lh->maketext('[asis,CSF] is installed, but [asis,LFD] is not running.'),
                    'suggestion' => $self->_lh->maketext(
                        'Click “lfd Restart” in the “[output,url,_1,_2,_3,_4]” area. Alternately, run “[asis,csf --lfd restart]” from the command line.',
                        $self->base_path('cgi/configserver/csf.cgi'),
                        'ConfigServer Security & Firewall',
                        'target',
                        '_blank'
                    ),
                }
            );
            return 1;
        }

        # Nothing's in place and the cPanel UI doesn't seem to be there??
        $security_advisor_obj->add_advice(
            {
                'key'        => 'Brute_csf_installed_lfd_not_running_2',
                'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                'text'       => $self->_lh->maketext('[asis,CSF] is installed, but [asis,LFD] is not running.'),
                'suggestion' => $self->_lh->maketext('Run “[asis,csf --lfd restart]“ from the command line.'),
            }
        );
    }

    my $imunify360 = Whostmgr::Imunify360->new();
    if ( $imunify360->is_running() ) {

        # If it is not running the check_config result would not be valid. The Imunify360 assessor module will add advice to start the service.
        if ( $imunify360->check_config( sub { shift()->{'items'}{'PAM'}{'enable'} } ) ) {

            # No extra message here because the Imunify360 assessor module will already add one for Imunify360 itself
            return 1;
        }
        else {
            $security_advisor_obj->add_advice(
                {
                    'key'        => 'Brute_imunify360_pam_brute_force_protection_disabled',
                    'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                    'text'       => $self->_lh->maketext('[asis,Imunify360] is installed but [asis,PAM] brute-force attack protection is disabled.'),
                    'suggestion' => $self->_lh->maketext('Enable [asis,Imunify360] [asis,PAM] brute-force attack protection to ensure that your server is protected.'),
                }
            );

            # Don't return here because we also want the default advice below to be added if Imunify360 is not currently serving this purpose
        }
    }

    # No brute force is installed!
    $security_advisor_obj->add_advice(
        {
            'key'        => 'Brute_force_protection_not_enabled',
            'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
            'text'       => $self->_lh->maketext('No brute force protection detected'),
            'suggestion' => $self->_lh->maketext(
                'Enable cPHulk Brute Force Protection in the “[output,url,_1,cPHulk Brute Force Protection,_2,_3]” area.',
                $self->base_path('scripts7/cphulk/config'),
                'target',
                '_blank'

            ),
        }
    );

    return 1;
}

sub lfd_is_running {
    my $contents = Cpanel::LoadFile::load_if_exists("/var/run/lfd.pid") // return 0;
    my ($pid) = $contents =~ m/^\s*(\d+)/a;
    $pid = int( $pid || 0 );
    return 0 unless $pid;

    my $proc = Cpanel::PsParser::fast_parse_ps( 'want_pid' => $pid );
    $proc && ref $proc eq 'ARRAY' || return 0;
    $proc = $proc->[0] or return 0;

    return ( $proc->{'command'} =~ m{^lfd\b} ) ? 1 : 0;
}

1;
