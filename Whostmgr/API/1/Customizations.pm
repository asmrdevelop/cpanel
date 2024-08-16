# cpanel - Whostmgr/API/1/Customizations.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::API::1::Customizations;

=head1 NAME

Whostmgr::API::1::Customizations - API functions for managing root and reseller Customization settings.

=head1 SYNOPSIS

    use Whostmgr::API::1::Customizations ();
    my $result = Whostmgr::API::1::Customizations::update_customizations (
        {
            'application' => 'cpanel',
            'theme'       => 'jupiter',
            'brand        => {
                #Supply your branding data as a hash structure (see "branding" argument below).
                }
        },
    );

=cut

use cPstrict;
use Cpanel::JSON             ();
use Cpanel::APICommon::Error ();
use Whostmgr::Customizations ();

use constant NEEDS_ROLE => {
    retrieve_customizations => undef,
    update_customizations   => undef,
    delete_customizations   => undef,
};

=head1 METHODS

=head2 update_customizations

Add or update customization settings for a specific application and theme.
See openapi for further documentation.

=cut

sub update_customizations {
    my ( $args, $metadata ) = @_;
    my $result = {};

    my $application = $args->{'application'};
    my $theme       = $args->{'theme'};
    my $data_json   = $args->{'data'} || $args->{'brand'};    # repackage brand for backwards compatability

    if ( !$application ) {
        $metadata->set_not_ok("The 'application' parameter is required.");
        return;
    }

    if ( !$theme ) {
        $metadata->set_not_ok("The 'theme' parameter is required.");
        return;
    }

    if ( !$data_json ) {
        $metadata->set_not_ok("Either the 'brand' or 'data' parameter is required.");
        return;
    }

    my $data       = Cpanel::JSON::Load($data_json);
    my $add_result = Whostmgr::Customizations::add( $ENV{'REMOTE_USER'}, $application, $theme, $data );

    if ( $add_result->{'warnings'} && @{ $add_result->{'warnings'} } ) {
        $metadata->add_warning($_) for $add_result->{'warnings'}->@*;
    }

    if ( $add_result->{'errors'} && @{ $add_result->{'errors'} } ) {
        $metadata->set_not_ok("@{$add_result->{'errors'}}");
        return Cpanel::APICommon::Error::convert_to_payload( 'Invalid', errors => $add_result->{'errors'} );
    }

    $metadata->set_ok();
    return;

}

=head2 retrieve_customizations

This allows you to retrieve branding data for a specific application and theme.
See openapi for further documentation.

=cut

sub retrieve_customizations {
    my ( $args, $metadata ) = @_;

    my $application = $args->{'application'};
    my $theme       = $args->{'theme'};

    if ( !$application ) {
        $metadata->set_not_ok("The 'application' parameter is required.");
        return;
    }

    if ( !$theme ) {
        $metadata->set_not_ok("The 'theme' parameter is required.");
        return;
    }

    my $result = Whostmgr::Customizations::get( $ENV{'REMOTE_USER'}, $application, $theme );
    if ($result) {
        $metadata->set_ok();
    }
    else {
        $metadata->set_not_ok("No customization entry found for $theme-$application.");
    }

    return $result;
}

=head2 delete_customizations

Deletes the customization entry for an app and theme.
See openapi for further documentation.

=cut

sub delete_customizations {
    my ( $args, $metadata ) = @_;

    my $application = $args->{'application'};
    my $theme       = $args->{'theme'};
    my $path        = $args->{'path'};

    if ( !$application ) {
        $metadata->set_not_ok("The 'application' parameter is required.");
        return;
    }

    if ( !$theme ) {
        $metadata->set_not_ok("The 'theme' parameter is required.");
        return;
    }

    my $result = Whostmgr::Customizations::delete( $ENV{'REMOTE_USER'}, $application, $theme, $path );
    if ($result) {
        $metadata->set_ok();
    }
    else {
        $metadata->set_not_ok("No customization entry found for $theme-$application.");
    }
    return;
}

1;
