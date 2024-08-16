package Cpanel::API::Features;

# cpanel - Cpanel/API/Features.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel           ();
use Cpanel::Features ();

sub has_feature {
    my ( $args, $result ) = @_;

    if ( my $feature_name = $args->get('name') ) {
        my %valid_features = map { $_ => 1 } Cpanel::Features::load_all_feature_names();
        if ( !$valid_features{$feature_name} ) {
            $result->data(undef);
        }
        elsif ( Cpanel::hasfeature($feature_name) ) {
            $result->data(1);
        }
        else {
            $result->message( 'The feature “[_1]” exists but is not enabled.', $feature_name );
            $result->data(0);
        }
        return 1;
    }

    $result->error('You must specify a feature name.');
    return 0;
}

sub list_features {
    my ( $args, $result ) = @_;
    my %feature_to_status = map { $_ => Cpanel::hasfeature($_) } Cpanel::Features::load_all_feature_names();
    $result->data( \%feature_to_status );
    return 1;
}

sub get_feature_metadata {

    my ( undef, $result ) = @_;

    my $attributes_for_feature = Cpanel::Features::load_all_feature_metadata();

    if ( scalar @$attributes_for_feature ) {
        $result->data($attributes_for_feature);
        return 1;
    }

    $result->error('Unable to retrieve feature list.');

    return 0;
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    has_feature   => $allow_demo,
    list_features => $allow_demo,
);

1;
