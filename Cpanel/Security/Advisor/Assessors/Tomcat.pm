package Cpanel::Security::Advisor::Assessors::Tomcat;

# cpanel - Cpanel/Security/Advisor/Assessors/Tomcat.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use base 'Cpanel::Security::Advisor::Assessors';

sub generate_advice {
    my ($self) = @_;
    $self->_is_tomcat5_installed();

    return 1;
}

sub _is_tomcat5_installed {
    my ($self) = @_;
    my $security_advisor_obj = $self->{'security_advisor_obj'};

    if ( -l '/usr/local/jakarta/tomcat' ) {
        $security_advisor_obj->add_advice(
            {
                'key'        => q{Tomcat_installed_5_5_version_is_EOL},
                'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                'text'       => $self->_lh->maketext('Tomcat 5.5 is installed, but is EOL.'),
                'suggestion' => $self->_lh->maketext(
                    'Rebuild “[output,url,_1,EasyApache,_2,_3]” without Tomcat 5.5.x selected (or select the newest version of Tomcat), and manually remove the old Tomcat files.',
                    $self->base_path('cgi/easyapache.pl?action=_pre_cpanel_sync_screen'), 'target', '_blank',
                ),
            }
        );
    }

    return 1;
}

1;
