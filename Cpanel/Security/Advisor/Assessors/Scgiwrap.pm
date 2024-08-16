package Cpanel::Security::Advisor::Assessors::Scgiwrap;

# cpanel - Cpanel/Security/Advisor/Assessors/Scgiwrap.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Cpanel::Security::Advisor::Assessors';

use Cpanel::ConfigFiles::Apache ();
use Cpanel::SafeRun::Simple     ();

sub generate_advice {
    my ($self) = @_;
    $self->_check_scgiwrap;

    return 1;
}

sub _binary_has_setuid {
    my ($binary) = @_;
    return ( ( stat $binary )[2] || 0 ) & 04000;
}

sub _check_scgiwrap {
    my ($self) = @_;

    my $security_advisor_obj = $self->{'security_advisor_obj'};

    my $apacheconf = Cpanel::ConfigFiles::Apache->new();
    my $suexec     = $apacheconf->bin_suexec();
    my $httpd      = $apacheconf->bin_httpd();

    #check for sticky bit on file to see if it is enabled or not.
    my $suenabled = _binary_has_setuid($suexec);

    if ( -f $suexec ) {

        # patches welcome for more a robust way to do this besides matching getcap output!
        my $gc = Cpanel::SafeRun::Simple::saferunnoerror(qw[ getcap $suexec ]);    # the RPM in ea4 uses capabilities for setuid, not setuid bit
        $suenabled = $gc =~ m/cap_setgid/ && $gc =~ m/cap_setuid/;

        # CloudLinux's EA 4 RPM uses setuid.
        $suenabled ||= _binary_has_setuid($suexec);
    }

    #check for sticky bit on file to see if it is enabled or not.
    my $scgiwrap    = '/usr/local/cpanel/cgi-sys/scgiwrap';
    my $scgienabled = grep { ( ( stat $_ )[2] || 0 ) & 04000 } ( $scgiwrap, $scgiwrap . '_deprecated' );    # look for both

    my ($ruid) = ( grep { /ruid2_module/ } split( /\n/, Cpanel::SafeRun::Simple::saferun( $httpd, '-M' ) ) );

    if ( $suenabled && !$scgienabled ) {
        $security_advisor_obj->add_advice(
            {
                'key'  => 'Scgiwrap_SCGI_is_disabled',
                'type' => $Cpanel::Security::Advisor::ADVISE_GOOD,
                'text' => $self->_lh->maketext('SCGI is disabled, currently using the recommended suEXEC.'),
            }
        );
    }
    elsif ( $suenabled && $scgienabled ) {
        if ( !$ruid ) {
            $security_advisor_obj->add_advice(
                {
                    'key'        => 'Scgiwrap_SCGI_AND_suEXEC_are_enabled',
                    'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                    'text'       => $self->_lh->maketext('Both SCGI and suEXEC are enabled.'),
                    'suggestion' => $self->_lh->maketext(
                        'On the “[output,url,_1,Configure PHP and suEXEC,_2,_3]” page toggle “Apache suEXEC” off then back on to disable SCGI.',
                        $self->base_path('scripts2/phpandsuexecconf'),
                        'target',
                        '_blank'
                    ),
                }
            );
        }
        else {
            $security_advisor_obj->add_advice(
                {
                    'key'  => 'Scgiwrap_SCGI_suEXEC_and_mod_ruid2_are_enabled',
                    'type' => $Cpanel::Security::Advisor::ADVISE_GOOD,
                    'text' => $self->_lh->maketext('SCGI, suEXEC, and mod_ruid2 are enabled.'),
                }
            );
        }
    }
    elsif ( !$suenabled || -f "$suexec.disable" ) {
        if ( !$ruid ) {
            $security_advisor_obj->add_advice(
                {
                    'key'        => 'Scgiwrap_suEXEC_is_disabled',
                    'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                    'text'       => $self->_lh->maketext('suEXEC is disabled.'),
                    'suggestion' => $self->_lh->maketext(
                        'Enable suEXEC on the “[output,url,_1,Configure PHP and suEXEC,_2,_3]” page.',
                        $self->base_path('scripts2/phpandsuexecconf'),
                        'target',
                        '_blank'
                    ),
                }
            );
        }
        else {
            $security_advisor_obj->add_advice(
                {
                    'key'  => 'Scgiwrap_suEXEC_is_disabled_mod_ruid2_is_installed',
                    'type' => $Cpanel::Security::Advisor::ADVISE_GOOD,
                    'text' => $self->_lh->maketext('suEXEC is disabled; however mod_ruid2 is installed.'),
                }
            );
        }
    }
    else {
        $security_advisor_obj->add_advice(
            {
                'key'        => 'Scgiwrap_SCGI_is_enabled',
                'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                'text'       => $self->_lh->maketext('SCGI is enabled.'),
                'suggestion' => $self->_lh->maketext(
                    'Turn off SCGI and enable the more secure suEXEC in the “[output,url,_1,Configure PHP and suEXEC,_2,_3]” page.',
                    $self->base_path('scripts2/phpandsuexecconf'),
                    'target',
                    '_blank'
                ),
            }
        );

    }

    return 1;
}
1;
