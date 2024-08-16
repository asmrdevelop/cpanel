package Cpanel::Security::Advisor::Assessors::_Self;

# cpanel - Cpanel/Security/Advisor/Assessors/_Self.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use base 'Cpanel::Security::Advisor::Assessors';

use Cpanel::RPM::Versions::File ();
use Cpanel::OS                  ();

# The purpose of this assessor module is to report conditions which may render
# the provided advice untrustworthy or invalid. Currently, this is limited to
# determining whether the RPM database is acting as expected, since several
# other assessors rely on good RPM data.

# Logic behind this number: A barebones CentOS 6 container has 129(?) RPM packages.
# Round down to one significant figure.
use constant OS_RPM_COUNT_WARN_THRESHOLD => 100;

sub version { return '1.01'; }

sub generate_advice {
    my ($self) = @_;

    $self->_check_rpm() if $self->_distro_uses_rpm();

    return 1;
}

sub _check_rpm {
    my ($self) = @_;

    # Both primes the cache and ensures that the test is run.
    my $installed_rpms = $self->get_installed_rpms();

    my $cache = $self->{'security_advisor_obj'}->{'_cache'};
    if ( exists $cache->{'timed_out'} && $cache->{'timed_out'} ) {
        $self->add_bad_advice(
            'key'          => 'RPM_timed_out',
            'text'         => $self->_lh->maketext('Security Advisor timed out while reading the RPM database of packages.'),
            'suggestion'   => $self->_lh->maketext( "Security Advisor may include inaccurate results until it can fully read the RPM database. To resolve this, reduce the load on your system and then rebuild the RPM database with the following interface: [output,url,_1,Rebuild RPM Database,_2,_3].", $self->base_path('scripts/dialog?dialog=rebuildrpmdb'), 'target', '_blank' ),
            'block_notify' => 1,
        );
    }
    elsif ( exists $cache->{'died'} && $cache->{'died'} ) {
        $self->add_bad_advice(
            'key'          => 'RPM_broken',
            'text'         => $self->_lh->maketext('Security Advisor detected RPM database corruption.'),
            'suggestion'   => $self->_lh->maketext( "Security Advisor may include inaccurate results until it can cleanly read the RPM database. To resolve this, rebuild the RPM database with the following interface: [output,url,_1,Rebuild RPM Database,_2,_3].", $self->base_path('scripts/dialog?dialog=rebuildrpmdb'), 'target', '_blank' ),
            'block_notify' => 1,
        );
    }
    elsif ( ref $installed_rpms eq 'HASH' && scalar keys %$installed_rpms <= scalar( keys %{ Cpanel::RPM::Versions::File->new()->list_rpms_in_state('installed') } ) + OS_RPM_COUNT_WARN_THRESHOLD ) {
        $self->add_warn_advice(
            'key'          => 'RPM_too_few',
            'text'         => $self->_lh->maketext('The RPM database is smaller than expected.'),
            'suggestion'   => $self->_lh->maketext("Security Advisor may include inaccurate results if the RPM database of packages is incomplete. To resolve this, check the cPanel update logs for RPM issues."),
            'block_notify' => 1,
        );
    }

    return;
}

sub _distro_uses_rpm {
    return Cpanel::OS::is_rpm_based();
}

1;
