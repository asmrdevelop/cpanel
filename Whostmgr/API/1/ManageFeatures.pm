package Whostmgr::API::1::ManageFeatures;

# cpanel - Whostmgr/API/1/ManageFeatures.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Logger ();

use constant NEEDS_ROLE => {
    manage_features => undef,
};

my $logger = Cpanel::Logger->new();

sub _get_manager {
    require Cpanel::FeatureShowcase;
    require Cpanel::FeatureShowcase::Display;
    my $obj = Cpanel::FeatureShowcase->new();
    return unless $obj;
    Cpanel::FeatureShowcase::Display::limit_to_valid_interfaces(
        $obj,
        [$Cpanel::FeatureShowcase::Display::API]
    );
    return $obj;
}

sub _enable_disable_features {
    my ( $args, $meta_data, $action ) = @_;
    my @error_strings = ();
    my @actions_taken = ();

    require Cpanel::FeatureShowcase;

    # check to see if "features" argument
    # exists

    if ( !exists $args->{'features'} ) {
        push @error_strings, "At least one feature must be specified.";
    }
    else {

        # if the features parameter exists, it should contain
        # one or more feature names in a comma-delimited string
        # split this string into an array

        my @features = split( /\s*,\s*/, $args->{'features'} );

        # make sure the array contains at least one feature name

        if ( scalar @features == 0 ) {
            push @error_strings, "At least one feature must be specified.";
        }
        else {
            my $showcase = _get_manager();
            if ($showcase) {

                my $valid_features     = $showcase->_get_drivers();
                my @processed_features = ();

                foreach my $feature (@features) {

                    my %action_result;
                    $action_result{'feature'} = $feature;

                    if ( exists $valid_features->{$feature} ) {

                        # the feature name is valid

                        $showcase->action( $action, $feature );

                        $action_result{'status'} = ( scalar $showcase->errors() ) ? "Could not perform '$action' for $feature" : "Successfully performed '$action' for $feature";
                        push @processed_features, $feature;

                        # if there was some sort of error recorded
                        # by the showcase object, add it to the
                        # error list

                        if ( scalar $showcase->errors() ) {
                            push @error_strings, $showcase->flush_errors();
                        }
                    }
                    else {
                        $action_result{'status'} = "skipped";
                        push @error_strings, "$feature is not a valid feature.";
                    }

                    push @actions_taken, \%action_result;
                }

                $showcase->mark_features_as_viewed( $Cpanel::FeatureShowcase::SOURCE_API, @processed_features );
            }
            else {
                push @error_strings, 'Failed to load feature manager.';
            }
        }

    }

    # log any recorded errors

    if ( scalar @error_strings > 0 ) {
        $meta_data->{'errors'} = { 'error' => \@error_strings };
        foreach (@error_strings) {
            $logger->warn($_);
        }
    }

    # fill in the meta data results fields

    $meta_data->{'reason'} = ( @error_strings > 0 ) ? 'errors recorded' : 'OK';
    $meta_data->{'result'} = ( @error_strings > 0 ) ? 0                 : 1;

    return {} if !scalar @actions_taken;
    return { 'action' => \@actions_taken };
}

# display feature information
sub _getfeatureinfo {
    my ( $args,          $metadata )     = @_;
    my ( $error_strings, $feature_data ) = _featureinfo($args);

    $metadata->{'reason'} = 'OK';
    $metadata->{'result'} = 1;

    if ( scalar @{$error_strings} > 0 ) {
        $metadata->{'reason'} = 'errors recorded';
        $metadata->{'result'} = 0;
        $metadata->{'errors'} = { 'error' => $error_strings };

        foreach ( @{$error_strings} ) {
            $logger->warn($_);
        }
    }

    return {} if !scalar @{$feature_data};
    return { 'feature' => $feature_data };
}

sub _featureinfo {
    my ($args) = @_;
    my $manager = _get_manager();

    return ( ['Failed to load feature manager.'], [] ) unless $manager;

    my @feature_data;
    my @error_string;
    my @features;
    my $valid_features = $manager->_get_drivers();

    if ( exists $args->{'features'} ) {
        @features = split( /\s*,\s*/, $args->{'features'} );
    }
    else {
        push @features, keys %{$valid_features};
    }

    foreach (@features) {
        if ( !exists $valid_features->{$_} ) {
            push( @error_string, "$_ is not a vaild feature key." );
            next;
        }

        my $driver = $manager->get_driver($_);
        my $meta   = $driver->meta();
        my %feature_details;
        $feature_details{'feature_key'} = $_;
        $feature_details{'description'} = $meta->abstract();
        $feature_details{'link'}        = $meta->url();
        $feature_details{'name'}        = $meta->name('long');
        $feature_details{'enabled'}     = $driver->status();
        $feature_details{'recommended'} = $meta->is_recommended() || 0;
        $feature_details{'vendor'}      = $meta->vendor();

        $feature_details{'since'} = $meta->since();
        delete $feature_details{'since'} if !$feature_details{'since'};

        push @feature_data, \%feature_details;
    }

    return ( \@error_string, \@feature_data );
}

# list_feature_showcase - This sub routine is used by the remote api call
# 'list_feature_showcase' to display a list of features with their current settings.
sub _list_feature_showcase {
    my ($metadata) = @_;
    my $features = _get_list_feature_showcase();
    $metadata->{'result'} = ( ref $features eq 'ARRAY' && scalar @{$features} ) ? 1    : 0;
    $metadata->{'reason'} = $metadata->{'result'}                               ? 'OK' : 'No features found.';

    return if !$metadata->{'result'};
    return { "feature" => $features };
}

# _get_list_feature_showcase - Is a private method which return an arrayref of
#  hashes of format: { <feature_key> => $driver, <enabled> => $setting } )
sub _get_list_feature_showcase {
    my $manager = _get_manager();
    return [] unless $manager;
    my @features;
    my $list = $manager->feature_info();

    if ( scalar @{$list} ) {
        foreach my $driver ( @{$list} ) {
            my %feature_entry;
            my $meta_obj    = $driver->meta();
            my $driver_name = $meta_obj->name('driver') || '';

            $feature_entry{'feature_key'} = $driver_name;
            $feature_entry{'enabled'}     = ( $driver->check() ) ? 1 : 0;

            push @features, \%feature_entry;
        }
    }

    return \@features;
}

sub manage_features {
    my ( $args, $metadata ) = @_;

    my $overall_result = 1;
    my $error_string;

    if ( !exists $args->{'action'} ) {
        $overall_result = 0;
        $error_string   = "action is required.";
    }
    else {
        my $action = $args->{'action'};

        if ( $action eq "enable" ) {
            return _enable_disable_features( $args, $metadata, 'enable' );
        }
        elsif ( $action eq "disable" ) {
            return _enable_disable_features( $args, $metadata, 'disable' );
        }
        elsif ( $action eq "info" ) {
            return _getfeatureinfo( $args, $metadata );
        }
        elsif ( $action eq "list" ) {
            return _list_feature_showcase($metadata);
        }
        else { $error_string = "Invalid action specified: $action"; }
    }
    $metadata->{'reason'} = 'OK';
    $metadata->{'result'} = 1;

    if ($error_string) {
        $metadata->{'reason'} = $error_string;
        $metadata->{'result'} = 0;
    }
    return;
}

1;
