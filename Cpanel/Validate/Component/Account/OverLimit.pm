package Cpanel::Validate::Component::Account::OverLimit;

# cpanel - Cpanel/Validate/Component/Account/OverLimit.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw ( Cpanel::Validate::Component );

use Cpanel::Exception               ();
use Cpanel::Config::LoadCpUserFile  ();
use Cpanel::Validate::ResourceLimit ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( ownership_user limit_name limit_display_name limit_current_count ));
    $self->add_optional_arguments(qw( current_limit ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ( $username, $limit_name, $display_name, $current_count, $current_limit ) = @{$self}{ $self->get_validation_arguments() };

    if ( !length $current_limit ) {
        my $cpuser_data = Cpanel::Config::LoadCpUserFile::loadcpuserfile($username);
        $current_limit = $cpuser_data->{$limit_name};
    }

    my $max_limit = Cpanel::Validate::ResourceLimit::resource_limit_normalization($current_limit);
    if ( !Cpanel::Validate::ResourceLimit::validate_resource_limit( $max_limit, $current_count ) ) {
        die Cpanel::Exception::create(
            'ResourceLimitReached',
            'You may not have more than [numf,_1] of the resource “[_2]”.',
            [
                $max_limit,
                $display_name,
            ],
        );
    }

    return;
}

1;
