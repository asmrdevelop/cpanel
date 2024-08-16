package Cpanel::Security::Policy::PasswordStrength::Config;

# cpanel - Cpanel/Security/Policy/PasswordStrength/Config.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#use strict;

use Cpanel::Locale::Lazy 'lh';

sub new {
    my ( $class, $policy ) = @_;
    die "No policy object supplied.\n" unless defined $policy;
    return bless { 'policy' => $policy }, $class;
}

sub config {
    my ($self) = @_;

    my $url = ( $ENV{'cp_security_token'} ? $ENV{'cp_security_token'} : '' ) . '/scripts/minpwstrength';
    return {
        'header' => lh()->maketext('Check Password Strength at Login'),
        'fields' => [
            {
                'text' => lh()->maketext( 'The actual required password strength is set at [output,url,_1,Password Strength Configuration,target,_blank].', $url ),
                'type' => 'msg',
            },
        ],
    };
}

1;
