package Cpanel::Security::Advisor::Assessors::Iptables;

# cpanel - Cpanel/Security/Advisor/Assessors/Iptables.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use base 'Cpanel::Security::Advisor::Assessors';
use Cpanel::SafeRun::Simple;

sub generate_advice {
    my ($self) = @_;
    $self->_is_iptables_active();

    return 1;
}

sub _is_iptables_active {

    my ($self) = @_;

    my $security_advisor_obj = $self->{'security_advisor_obj'};

    if ( -x '/etc/init.d/iptables' ) {
        my $status_check = Cpanel::SafeRun::Simple::saferunnoerror(qw[ /etc/init.d/iptables status ]);

        # need a better way to check this
        if ( $status_check =~ m/not running/i ) {
            $security_advisor_obj->add_advice(
                {
                    'key'        => 'Iptables_firewall_not_running',
                    'type'       => $Cpanel::Security::Advisor::ADVISE_BAD,
                    'text'       => $self->_lh->maketext('Firewall is not running'),
                    'suggestion' => $self->_lh->maketext('This might be a simple matter of executing “/etc/init.d/iptables start”'),
                },
            );
        }
    }

    return 1;
}

1;
