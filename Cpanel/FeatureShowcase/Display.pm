package Cpanel::FeatureShowcase::Display;

# cpanel - Cpanel/FeatureShowcase/Display.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
# Use ConfigObj to showcase particular features/software and mark them via
#  an interface

use Cpanel::Server::Type ();

# Interface types
our $CLI = 'CLI';
our $API = 'API';
our $GUI = 'GUI';

my $_hide;

# name start with underscore to be skipped by Cpanel::FeatureShowcase::get_modified_feature_showcase
sub _hide_file { '/var/cpanel/activate/features/disable_feature_showcase' }

# use a negative name as we will only use this condition
sub is_not_visible {
    my $force = shift || 0;

    return 1 if Cpanel::Server::Type::is_dnsonly();

    if ( !defined $_hide || $force ) {

        # local cache
        $_hide = ( -e _hide_file() ? 1 : 0 );
    }
    return $_hide;
}

# pass a feature showcase object and a list (array_ref) of the interfaces that
#  pertain to the object's implementation.  The sub will narrow the object's
#  internal driver list down to just the drivers which A) don't specify
#  a list of valid interfaces for it's use, or B) specify valid interfaces for
#  which there is at least one match against the provided list.
# See _filter_valid_interface for implementation details
sub limit_to_valid_interfaces {
    my ( $feature_showcase_obj, $interface_list ) = @_;

    return unless $feature_showcase_obj;
    my $filterObj = $feature_showcase_obj->get_filterObj();
    $filterObj->import( { 'valid_interface' => \&_filter_valid_interface, } );

    my $filterList = $filterObj->filter( 'valid_interface', $interface_list );

    my $refined = $filterList->to_hash() || {};
    $feature_showcase_obj->_set_driver_objects($refined);

    return 1;
}

# filter used by limit_to_valid_interface(); see those comments for general
#  behavior/use
# NOTE: it is assumed that since a feature showcase object is being past, the
#  internal driver list should already be paired down to those which 'are
#  showcased'
# NOTE: if the second argument is invalid or an empty list, no work will be
#  performed. e.g., you can't filter to only drivers which define that they
#  don't have a single valid interface...if that is the desired behavior, the
#  caller would filter for drivers that aren't showcased...if there needs to
#  be more specific filtering (aka was showcased but is no long a valid
#  target for any showcase interface) then a different filter should probably
#  be created
sub _filter_valid_interface {
    my ( $listObj, $interface_list ) = @_;
    if ( ref $interface_list ne 'ARRAY' || !scalar @{$interface_list} ) {
        return 1;
    }

    my $data = $listObj->to_hash();
    foreach my $name ( keys %{$data} ) {
        my $metaObj          = $data->{$name}->meta();
        my $showcase_details = $metaObj->showcase();

        if ( !scalar keys %{$showcase_details} ) {
            $listObj->remove($name);
        }
        elsif ( exists $showcase_details->{'valid_interfaces'} && ref( $showcase_details->{'valid_interfaces'} ) eq 'ARRAY' ) {
            my $is_valid;

            foreach my $interface (@$interface_list) {
                if ( $is_valid = grep { $_ =~ m/$interface/ } @{ $showcase_details->{'valid_interfaces'} } ) {
                    last;
                }
            }
            $listObj->remove($name) unless $is_valid;
        }
    }
    return 1;
}
1;
