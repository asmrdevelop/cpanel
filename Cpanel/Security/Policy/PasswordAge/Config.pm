package Cpanel::Security::Policy::PasswordAge::Config;

# cpanel - Cpanel/Security/Policy/PasswordAge/Config.pm
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
    my ( $self, $formref, $cpconf_ref, $is_save ) = @_;
    my $err;

    my $policy = $self->{'policy'};
    $policy->set_conf_value( $cpconf_ref, 'maxage', 90 ) unless $policy->conf_value( $cpconf_ref, 'maxage' );
    if ( $is_save and $formref->{'PasswordAge'} and exists $formref->{'maxage'} ) {
        my $maxage = int $formref->{'maxage'};
        if ( $maxage > 0 ) {
            $policy->set_conf_value( $cpconf_ref, 'maxage', $maxage );
        }
        else {
            $err = lh()->maketext('Password Age must be a number greater than 0.');
        }
    }

    return {
        'header' => lh()->maketext('Password Age'),
        ( $err ? ( 'error' => $err ) : () ),
        'fields' => [
            {
                'label'  => lh()->maketext('Maximum Password Age (in days):'),
                'id'     => 'maxage',
                'value'  => $policy->conf_value( $cpconf_ref, 'maxage' ),
                'minval' => 1
            },
        ],
    };
}

1;
