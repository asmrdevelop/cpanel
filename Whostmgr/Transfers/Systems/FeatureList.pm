package Whostmgr::Transfers::Systems::FeatureList;

# cpanel - Whostmgr/Transfers/Systems/FeatureList.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Try::Tiny;
use Cpanel::Exception              ();
use Cpanel::Config::LoadCpUserFile ();

use Cpanel::Features::Load ();

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_phase {
    return 10;
}

sub get_prereq {
    return ['Package'];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores the account’s feature list setting.') ];
}

sub get_restricted_available {
    return 1;
}

*unrestricted_restore = \&restricted_restore;

sub restricted_restore {
    my ($self) = @_;

    my $user = $self->newuser();

    my $cpuser_data = Cpanel::Config::LoadCpUserFile::load($user);

    # The feature list name was already validated in Whostmgr::Transfers::ArchiveManager::Validate
    # if this is a new account. So, we do not need to validate the feature list name here.

    my $feature_list = $cpuser_data->{'FEATURELIST'} || 'undefined';
    return ( 1, 'Feature list is not set.' ) if $feature_list eq 'undefined';

    if ( $feature_list ne 'default' && !-e Cpanel::Features::Load::featurelist_file($feature_list) ) {
        my $setting_default_error_obj;
        try {
            $self->_set_cpuser_keys_to_default( $user, ['FEATURELIST'] );
        }
        catch {
            $setting_default_error_obj = $_;
        };

        if ($setting_default_error_obj) {
            return ( 0, Cpanel::Exception::get_string($setting_default_error_obj) );
        }

        $self->warn( $self->_locale()->maketext( 'The feature list “[_1]” does not exist on the system. The feature list setting for the user “[_2]” has been set to [output,asis,default].', $feature_list, $user ) );
        return ( 1, 'Feature list set to default.' );
    }

    return ( 1, 'Feature list exists.' );
}

1;
