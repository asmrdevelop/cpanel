package Whostmgr::Transfers::Session::Items::FeatureListRemoteRoot;

# cpanel - Whostmgr/Transfers/Session/Items/FeatureListRemoteRoot.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.0';

use Cpanel::Features::Migrate ();

use parent qw(Whostmgr::Transfers::Session::Items::FileBase Whostmgr::Transfers::Session::Items::Schema::FeatureListRemoteRoot);

sub module_info {
    my ($self) = @_;

    return {
        'dir'       => '/var/cpanel/features',
        'perms'     => 0755,
        'item_name' => $self->_locale()->maketext('Feature List'),
    };
}

sub post_transfer {
    my ($self) = @_;

    my ( $status, $modified ) = Cpanel::Features::Migrate::migrate_feature_list_to_current( $self->item() );
    if ($status) {
        print $self->_locale()->maketext( "The “[_1]” featurelist migrated successfully.", $self->item() ) . "\n";
    }
    else {
        return ( 0, $self->_locale()->maketext( "The “[_1]” featurelist could not be migrated.", $self->item() ) );
    }
    if ($modified) {
        print $self->_locale()->maketext( "The “[_1]” featurelist was modified successfully.", $self->item() ) . "\n";
    }

    return ( 1, "Feature list migrated" );
}

1;
