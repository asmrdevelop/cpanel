package Cpanel::Security::Advisor::Assessors::Passwords;

# cpanel - Cpanel/Security/Advisor/Assessors/Passwords.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Cpanel::Security::Advisor::Assessors';

sub generate_advice {
    my ($self) = @_;
    $self->_check_for_low_pwstrength;

    return 1;
}

sub _check_for_low_pwstrength {
    my ($self) = @_;

    my $security_advisor_obj = $self->{'security_advisor_obj'};

    if ( !$security_advisor_obj->{'cpconf'}->{'minpwstrength'} || $security_advisor_obj->{'cpconf'}->{'minpwstrength'} < 25 ) {
        $security_advisor_obj->add_advice(
            {
                'key'        => 'Passwords_weak_permitted',
                'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                'text'       => $self->_lh->maketext('Trivially weak passwords are permitted.'),
                'suggestion' => $self->_lh->maketext(
                    'Configure Password Strength requirements in the “[output,url,_1,Password Strength Configuration,_2,_3]” area',
                    $self->base_path('scripts/minpwstrength'),
                    'target',
                    '_blank'
                ),
            }
        );

    }
    elsif ( $security_advisor_obj->{'cpconf'}->{'minpwstrength'} < 50 ) {
        $security_advisor_obj->add_advice(
            {
                'key'        => 'Passwords_strength_requirements_are_low',
                'type'       => $Cpanel::Security::Advisor::ADVISE_WARN,
                'text'       => $self->_lh->maketext('Password strength requirements are low.'),
                'suggestion' => $self->_lh->maketext(
                    'Configure a Default Password Strength of at least 50 in the “[output,url,_1,Password Strength Configuration,_2,_3]” area',
                    $self->base_path('scripts/minpwstrength'),
                    'target',
                    '_blank'
                ),
            }
        );

    }
    elsif ( $security_advisor_obj->{'cpconf'}->{'minpwstrength'} < 65 ) {
        $security_advisor_obj->add_advice(
            {
                'key'        => 'Passwords_strength_requirements_are_moderate',
                'type'       => $Cpanel::Security::Advisor::ADVISE_INFO,
                'text'       => $self->_lh->maketext('Password strength requirements are moderate.'),
                'suggestion' => $self->_lh->maketext(
                    'Configure a Default Password Strength of at least 65 in the “[output,url,_1,Password Strength Configuration,_2,_3]” area',
                    $self->base_path('scripts/minpwstrength'),
                    'target',
                    '_blank'
                ),
            }
        );

    }
    else {
        $security_advisor_obj->add_advice(
            {
                'key'  => 'Passwords_strengths_requirements_are_strong',
                'type' => $Cpanel::Security::Advisor::ADVISE_GOOD,
                'text' => $self->_lh->maketext('Password strength requirements are strong.'),
            }
        );
    }

    return 1;
}

1;
