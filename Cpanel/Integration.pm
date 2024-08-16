package Cpanel::Integration;

# cpanel - Cpanel/Integration.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::Autodie                      ();
use Cpanel::FileUtils::Dir               ();
use Cpanel::Integration::Config          ();
use Cpanel::AdminBin::Serializer         ();
use Cpanel::Validate::FilesystemNodeName ();

=head1 NAME

Cpanel::Integration

=head1 DESCRIPTION

Load admin and user integration configuration for an application

=cut

=head1 SYNOPSIS

    use Cpanel::Integration ();

    my $user_config = Cpanel::Integration::load_user_app_config($user, $app);
    my $admin_config = Cpanel::Integration::load_admin_app_config($user, $app);


=cut

=head1 DESCRIPTION

=head2 load_admin_app_config

=head3 Purpose

Read and deserialize the configuration for a single app per user that only
the admin is allowed to see.  Typically this contains a token that is used
to generate an autologin url for the app.

=head3 Arguments

=over

=item $user: string - The cPanel user who has the app installed

=item $app: string - The app to read the configuration for (this should match the one provided to the WHM create_integration_link API)

=back

=head3 Returns

=over

=item A deserialized version of the app's admin readable integration configuration.

=back

Example:

C<<
{
   "token" : "frogger"
}
>>

If an error occurs, the function will throw an exception.

=cut

sub load_admin_app_config {
    my ( $user, $app ) = @_;

    _validate_user_app( $user, $app );

    #Cpanel::Transaction::File::JSONReader, as of September 2015,
    #does not throw on nonexistent files.
    #TODO: ^^ That probably is not optimal behavior; change that,
    #then update this to use that module.

    return Cpanel::AdminBin::Serializer::LoadFile( Cpanel::Integration::Config::get_app_config_path_for_admin( $user, $app ) );
}

=head2 load_user_group_config

=head3 Purpose

Read and deserialize the configuration for a single group per user

=head3 Arguments

=over

=item $user: string - The cPanel user who has the group installed

=item $group: string - The group to read the configuration for (this should match the one provided to the WHM create_integration_link API)

=back

=head3 Returns

=over

=item A deserialized version of the group's user readable integration configuration

=back

Example:

C<<
{
   "group" : "WHMCS"
   "user" : "nick",
   "label" : "WHMCS Customer Service",
}
>>

If an error occurs, the function will throw an exception.

=cut

sub load_user_group_config {
    my ( $user, $group ) = @_;

    _validate_user_app( $user, $group );

    my $resp = Cpanel::AdminBin::Serializer::LoadFile( Cpanel::Integration::Config::get_user_group_config_path( $user, $group ) );

    return $resp;
}

#----------------------------------------------------------------------

=head2 load_user_app_config

=head3 Purpose

Read and deserialize the configuration for a single app per user

=head3 Arguments

=over

=item $user: string - The cPanel user who has the app installed

=item $app: string - The app to read the configuration for (this should match the one provided to the WHM create_integration_link API)

=back

=head3 Returns

=over

=item A deserialized version of the app's user readable integration configuration

=back

Example:

C<<
{
   "app" : "WHMCS_customer_service",
   "base64_png_image" : "iVBORw0KGgoAAAANSUhEUgAAADAAAAA....",
   "user" : "nick",
   "url" : "http://www.cpanel.net",
   "label" : "WHMCS Customer Service",
   "autologin_token_url" : "http://www.koston.org/login.cgi",
   "implements" : "customer_service"
}
>>

If an error occurs, the function will throw an exception.

=cut

sub load_user_app_config {
    my ( $user, $app ) = @_;

    _validate_user_app( $user, $app );

    my $resp = Cpanel::AdminBin::Serializer::LoadFile( Cpanel::Integration::Config::get_app_config_path_for_user( $user, $app ) );

    return $resp;
}

#----------------------------------------------------------------------

=head2 get_dynamicui_files_for_user( USER )

=head3 Purpose

Get a list of filesystem paths that contain integration DynamicUI files
for the given user.

=head3 Arguments

=over

=item USER: string - The cPanel user who has the app(s) installed

=back

=head3 Returns

=over

=item A list of the filesystem paths. Order is not defined.

=back

=cut

sub get_dynamicui_files_for_user {
    my ($user) = @_;

    my $dynamicui_integration_dir = Cpanel::Integration::Config::dynamicui_dir_for_user($user);

    return if !Cpanel::Autodie::exists($dynamicui_integration_dir);

    return map { index( $_, 'dynamicui_' ) == 0 ? "$dynamicui_integration_dir/$_" : () } @{ Cpanel::FileUtils::Dir::get_directory_nodes($dynamicui_integration_dir) };
}

#----------------------------------------------------------------------

sub _validate_user_app {
    my ( $user, $app ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($user);
    Cpanel::Validate::FilesystemNodeName::validate_or_die($app);

    return;
}

1;
