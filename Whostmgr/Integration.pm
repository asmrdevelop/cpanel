package Whostmgr::Integration;

# cpanel - Whostmgr/Integration.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

=encoding UTF-8

Whostmgr::Integration

=head1 DESCRIPTION

root level functions related to Integration.

=cut

=head1 SYNOPSIS

    use Whostmgr::Integration;

    Whostmgr::Integration::add_link(
        $username,
        'my_token_app',
        {
            'url'                 => 'http://www.cpanel.com/fallback.cgi',
            'autologin_token_url' => 'http://www.cpanel.com/login.cgi',
            'token'               => '94e48bf7350eaae85a6b4c3d829a1994',
            'subscriber_unique_id'=> '934754893574289574895437589',
            'implements'          => 'support',
            'label'               => '[asis,cPanel] Support',
            'order'               => -6,
            'group_id'            => 'pref',
            'hide'              => '1',
        }
    );

    Whostmgr::Integration::update_token(
        $username,
        'my_token_app',
        {
            'token'               => '94e48bf7350eaae85a6b4c3d829a1994-2',
        }
    );

    Whostmgr::Integration::remove_link(
        $username,
        'my_token_app',
    );


=cut

=head1 DESCRIPTION

=cut

use strict;
use warnings;

use Try::Tiny;

use MIME::Base64 ();

use Cpanel::Validate::FilesystemNodeName  ();
use Cpanel::Autodie                       ();
use Cpanel::CommandQueue                  ();
use Cpanel::Config::LoadCpUserFile        ();
use Cpanel::Encoder::URI                  ();
use Cpanel::Exception                     ();
use Cpanel::FileType                      ();
use Cpanel::FileUtils::Write              ();
use Cpanel::Integration::Config           ();
use Cpanel::JSON                          ();
use Cpanel::Themes::Assets::Link          ();
use Cpanel::Themes::Assets::Group         ();
use Cpanel::Themes::Serializer::DynamicUI ();
use Cpanel::Themes::Utils                 ();
use Cpanel::Validate::Base64              ();

use Whostmgr::Integration::Purge ();
*purge_user = *Whostmgr::Integration::Purge::purge_user;

my $DEFAULT_IMAGE =
  'iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABg2lDQ1BJQ0MgcHJvZmlsZQAAKJF9kT1Iw0AcxV9TRZEWh3aQ4pChOlkQFXHUKhShQqgVWnUwufQLmjQkKS6OgmvBwY/FqoOLs64OroIg+AHi5uak6CIl/i8ptIjx4Lgf7+497t4BQrPKNKtnHNB028ykkmIuvyr2vSIEARGEEZOZZcxJUhq+4+seAb7eJXiW/7k/R1gtWAwIiMSzzDBt4g3i6U3b4LxPHGVlWSU+Jx4z6YLEj1xXPH7jXHJZ4JlRM5uZJ44Si6UuVrqYlU2NeIo4rmo65Qs5j1XOW5y1ap2178lfGCroK8tcpzmMFBaxBAkiFNRRQRU2ErTqpFjI0H7Sxx9z/RK5FHJVwMixgBo0yK4f/A9+d2sVJye8pFAS6H1xnI8RoG8XaDUc5/vYcVonQPAZuNI7/loTmPkkvdHR4kfA4DZwcd3RlD3gcgcYejJkU3alIE2hWATez+ib8kDkFhhY83pr7+P0AchSV+kb4OAQGC1R9rrPu/u7e/v3TLu/HyCgcoYi2AMsAAAABmJLR0QA4gCkAMTpL9zVAAAACXBIWXMAAA3XAAAN1wFCKJt4AAAAB3RJTUUH5QwCEw0ukrxrsAAAAlJJREFUaN7tl89LVFEUxz/n3plJx4wgrCFzfv0FTUTRQmkocFMykZtaSUJ/RNBK6I8IbOtSEYoERdBwEYJGywJHW1hKIBEqjffdFr3CSOe9mXnjKN0PPLjwDuee7+Pdc88XHA6Hw9EA0uL9zwLD/noU2DpJHy+tRcqABay/TjdrsyvAO8D7veEBjwcs+7Fhil9NxpR5PZC1b+7nbWdC7WmR1VpFhP2FloFzwJhf6EEo4AHwFbhcJVePFplLaEm/vJNRxUsdACxt7lIcXzHfK+azsfQCK1EKMMAz4GlA3AjwBNBBxb+6m1E3uzv+elmPCBVSgPJFhBGqqhXfHpOemVL2n+IBCl1tzN7L6dNxndLCPJCLSkDD3UaLzCfj0jNdyukbqeShgYWuNqZLWZ2Mq5QWmfU7VcsFDHvWZqYGsvr6hfbA4Kvn25kayGrP2gzw6DgIaBpHJWBUiaz2T5bN4sZOYPDixg79k2WjfrXVF8dBwJaxtne7YteK4yvm7ZfDRSxt7nJ7omy2K966sbYYdDuHFeBVaY370VXuiU/G2r6dPbt2a+JgEfva6Lqx9IVpo7VeZM+BH4fEJIDHIS6yVFxk7lRM8jOlnL7mH+p6iq91lFgOOUoUQuTr1iIfOxNqb2EwbxcG8/ZMQpl6RolWcjGu5IOAlQaGuVaP0x3AQ/8sjgHfnMNxOI63I4va2R25I4vS2dWE8d1WECMBxieqPC1xZFHmcX7ACXAC/jcBUTiyKPP8IRZSwHtgyHdj1RzZkB/b7Dwtc2RROzuHw+FwOE42PwGJ5AsD4kvFbQAAAABJRU5ErkJggg==';

#exposed for testing
our @_LINK_OBJ_DEFAULTS = (
    base64_png_image => $DEFAULT_IMAGE,
    group_id         => 'preferences',
    order            => 99999,
    target           => '_blank',         #can’t be overridden
);

my @LINK_OBJ_OVERRIDABLE = qw(
  base64_png_image
  group_id
  hide
  implements
  order
);

=head2 add_link( USER, APP, LINK_DATA )

=head3 Purpose

Create an integration link with an external application for a user
that will appear in their cPanel UI

=head3 Arguments

=over

=item * USER: string (required) - The name of the user to create the integration link for. WE ASSUME THIS IS A VALID USERNAME AND DO NOT VALIDATE IT!!

=item * APP: string (required) - The name of the app that was provided when the integration link was created

=item * LINK_DATA: hashref (required)

=over

=item - 'label': string (optional) The text that goes with the icon in the cPanel UI. Defaults to APP.

=item - 'autologin_token_url': string (required or optional if url is provided) - A url endpoint that will provide a 'redirect_url' that will auto-login the user in

=item - 'url': string (required or optional if autologin_token_url is provided) - A url that the user will be redirected to when the autologin_token_url is not specified or cannot provide a auto-login url

=item - 'token': string (optional) - A token that will be presented to the autologin_token_url

=item - 'subscriber_unique_id': string (optional) - A subscriber_unique_id that will be presented to the autologin_token_url

=item - 'implements': string (optional) - An implementee as described by the get_users_links API. Defaults to the value of APP. (Check Cpanel::Themes::Assets::Link for validity.)

=item - 'base64_png_image': string (optional) - A based64-encoded PNG image that will be displayed for the app in the cPanel UI. Defaults to the image above.

=item - 'order': integer (optional) - The sort order of the app in the UI group that is displayed in the cPanel UI. Defaults to 99999. (Check Cpanel::Themes::Assets::Link for validity.)

=item - 'group_id': string (optional) - The DynamicUI group id.  Defaults to “pref”. (Check Cpanel::Themes::Assets::Link for validity.) cPanel UI currently use the following regex: mail|logs|files|domains|db|sec|software|pref|advanced

=item - 'hide': bool (optional) - If the link should be hidden from the UI.

=back

=back

=head3 Returns

=over

=item 1 on success

=back

If an error occurred the function will generate an exception

=cut

my @link_data_keys = qw(
  autologin_token_url
  base64_png_image
  group_id
  hide
  implements
  label
  order
  subscriber_unique_id
  token
  url
);

sub add_link {
    my ( $user, $app, $link_data ) = @_;

    _validate_user_app( $user, $app );

    my %link_data_copy = %{$link_data};
    _validate_data_and_remove_unknown_items( \%link_data_copy, \@link_data_keys );

    #“url” OR “autologin_token_url” is required.
    if ( !length $link_data->{'autologin_token_url'} && !length $link_data->{'url'} ) {

        #This error can go out to API callers, so it should be translated.
        die Cpanel::Exception->create( 'You must supply [numerate,_1,the following parameter,one of the following parameters]: [join,~, ,_2]', [ 2, [qw(autologin_token_url url)] ] );
    }

    if ( defined $link_data->{'hide'} ) {
        require Cpanel::Validate::Boolean;
        Cpanel::Validate::Boolean::validate_or_die( $link_data->{'hide'} );
    }

    my $token = delete $link_data_copy{'token'};

    my $user_config_path      = Cpanel::Integration::Config::get_app_config_path_for_user( $user, $app );
    my $admin_config_path     = Cpanel::Integration::Config::get_app_config_path_for_admin( $user, $app );
    my $dynamicui_config_path = Cpanel::Integration::Config::get_dynamicui_path_for_user_app( $user, $app );

    my $dynamic_ui_entry = _generate_dynamicui_entry_from_link_data( $user, $app, \%link_data_copy );

    return _run_creation_queue(
        [
            [
                $user_config_path,
                Cpanel::JSON::pretty_dump( \%link_data_copy ),
                $Cpanel::Integration::Config::USER_CONFIG_PERMS,
            ],
            [
                $admin_config_path,
                Cpanel::JSON::pretty_dump( { 'token' => $token } ),
                $Cpanel::Integration::Config::ADMIN_CONFIG_PERMS,
            ],
            [
                $dynamicui_config_path,
                Cpanel::JSON::pretty_dump( [$dynamic_ui_entry] ),
                $Cpanel::Integration::Config::USER_CONFIG_PERMS,
            ],
        ]
    );
}

=head2 add_group( USER, GROUPID, GROUP_DATA )

=head3 Purpose

Create a new group in the cPanel UI

=head3 Arguments

=over

=item * USER: string (required) - The name of the user to create the integration link for. WE ASSUME THIS IS A VALID USERNAME AND DO NOT VALIDATE IT!!

=item * GROUPID: string (required) - The name of the groupid to use for the group

=item * GROUP_DATA: hashref (required)

=over

=item - 'label': string (optional) The text that goes with the icon in the cPanel UI. Defaults to GROUPID.

=item - 'order': integer (optional) - The sort order of the group in the UI. Defaults to 99999. (Check Cpanel::Themes::Assets::Group for validity.)


=back

=back

=head3 Returns

=over

=item 1 on success

=back

If an error occurred the function will generate an exception

=cut

my @group_data_keys = qw(
  label
  order
);

sub add_group {
    my ( $user, $groupid, $group_data ) = @_;

    _validate_user_groupid( $user, $groupid );

    my %group_data_copy = %{$group_data};
    _validate_data_and_remove_unknown_items( \%group_data_copy, \@group_data_keys );

    my $user_config_path      = Cpanel::Integration::Config::get_user_group_config_path( $user, $groupid );
    my $dynamicui_config_path = Cpanel::Integration::Config::get_dynamicui_path_for_user_group( $user, $groupid );
    my $dynamic_ui_entry      = _generate_dynamicui_entry_from_group_data( $user, $groupid, \%group_data_copy );

    return _run_creation_queue(
        [
            [
                $user_config_path,
                Cpanel::JSON::pretty_dump( \%group_data_copy ),
                $Cpanel::Integration::Config::USER_CONFIG_PERMS,
            ],
            [
                $dynamicui_config_path,
                Cpanel::JSON::pretty_dump( [$dynamic_ui_entry] ),
                $Cpanel::Integration::Config::USER_CONFIG_PERMS,
            ],
        ]
    );
}

=head2 update_token( USER, APP, TOKEN )

=head3 Purpose

Update the token in an an intergration link for an app.

=head3 Arguments

=over

=item USER: string (required) - The user to update the token for

=item APP: string (required) - The name of the app that was provided when the integration link was created

=item TOKEN: string (optional) - A token that will be presented to the autologin_token_url

=back

=head3 Returns

=over

=item 1 on success

=back

If an error occurred the function will generate an exception

=cut

sub update_token {
    my ( $user, $app, $token ) = @_;

    _validate_user_app( $user, $app );

    my $admin_config_path = Cpanel::Integration::Config::get_app_config_path_for_admin( $user, $app );

    Cpanel::FileUtils::Write::overwrite( $admin_config_path, Cpanel::JSON::pretty_dump( { 'token' => $token } ), $Cpanel::Integration::Config::ADMIN_CONFIG_PERMS );

    return 1;
}

=head2 remove_link( USER, APP )

=head3 Purpose

Remove an intergration link for an app.

=head3 Arguments

=over

=item USER: string (required) - The user to remove the link for

=item APP: string (required) - The name of the app that was provided when the integration link was created

=back

=head3 Returns

=over

=item 1 on success

=back

If an error occurred the function will generate an exception

=cut

sub remove_link {
    my ( $user, $app ) = @_;

    _validate_user_app( $user, $app );

    my $user_config_path      = Cpanel::Integration::Config::get_app_config_path_for_user( $user, $app );
    my $admin_config_path     = Cpanel::Integration::Config::get_app_config_path_for_admin( $user, $app );
    my $dynamicui_config_path = Cpanel::Integration::Config::get_dynamicui_path_for_user_app( $user, $app );

    foreach my $config_path ( $user_config_path, $admin_config_path, $dynamicui_config_path ) {
        Cpanel::Autodie::unlink_if_exists($config_path);
    }
    return 1;
}

=head2 remove_group( USER, GROUPID )

=head3 Purpose

Remove a UI group from a user

=head3 Arguments

=over

=item USER: string (required) - The user to remove the group for

=item GROUPID: string (required) - The name of the groupid that was provided when the group was created

=back

=head3 Returns

=over

=item 1 on success

=back

If an error occurred the function will generate an exception

=cut

sub remove_group {
    my ( $user, $groupid ) = @_;

    _validate_user_groupid( $user, $groupid );

    my $user_config_path      = Cpanel::Integration::Config::get_user_group_config_path( $user, $groupid );
    my $dynamicui_config_path = Cpanel::Integration::Config::get_dynamicui_path_for_user_group( $user, $groupid );

    foreach my $config_path ( $user_config_path, $dynamicui_config_path ) {
        Cpanel::Autodie::unlink_if_exists($config_path);
    }
    return 1;
}

=head2 list_links(USER)

=head3 Purpose

List the app integration links for a user

=head3 Arguments

=over

=item 'USER': string (required) - The user to list the links for

=back

=head3 Returns

=over

=item An array of names of apps that are linked

=back

If an error occurred the function will generate an exception.

=cut

sub list_links {
    my ($user) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($user);

    return Cpanel::Integration::Config::get_app_links_for_user($user);
}

=head2 purge_user( USER )

=head3 Purpose

Remove all of a cPanel user’s integration data.

=over

=item * USER: string (required) - The user whose data to delete

=back

=cut

sub _generate_dynamicui_entry_from_group_data {
    my ( $user, $groupid, $group_data ) = @_;

    my $theme         = Cpanel::Config::LoadCpUserFile::load_or_die($user)->{'RS'};
    my $theme_docroot = Cpanel::Themes::Utils::get_theme_root($theme);
    my $dynamic_ui    = Cpanel::Themes::Serializer::DynamicUI->new( docroot => $theme_docroot, 'sources' => [] );

    my %group_obj_params = (
        id    => $groupid,
        order => $group_data->{'order'} || 99999,
        name  => sprintf( q<$LANG{'%s'}>, $group_data->{'label'} || $groupid ),
    );

    return $dynamic_ui->group2dui( Cpanel::Themes::Assets::Group->new(%group_obj_params) );
}

sub _generate_dynamicui_entry_from_link_data {
    my ( $user, $app, $link_data ) = @_;

    my $theme         = Cpanel::Config::LoadCpUserFile::load_or_die($user)->{'RS'};
    my $theme_docroot = Cpanel::Themes::Utils::get_theme_root($theme);
    my $dynamic_ui    = Cpanel::Themes::Serializer::DynamicUI->new( docroot => $theme_docroot, sources => [] );

    if ( $link_data->{'base64_png_image'} ) {
        try {
            Cpanel::Validate::Base64::validate_or_die( $link_data->{'base64_png_image'} );
        }
        catch {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not valid [asis,Base64].', ['base64_png_image'] );
        };

        my $binary = MIME::Base64::decode_base64( $link_data->{'base64_png_image'} );

        my $mime_type = Cpanel::FileType::determine_mime_type_from_stringref( \$binary );
        if ( !$mime_type || $mime_type ne 'image/png' ) {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,PNG] image.', ['base64_png_image'] );
        }
    }

    my %link_obj_params = (
        implements => $app,

        @_LINK_OBJ_DEFAULTS,

        ( map { $link_data->{$_} ? ( $_ => $link_data->{$_} ) : () } @LINK_OBJ_OVERRIDABLE ),

        #not overridable
        id   => $app,
        icon => $app,    #NOTE: This doesn’t seem to make it into the serialized DynamicUI??

        #NOTE: This is NOT the same as “url” that’s given to add_link().
        uri => 'integration/index.html?app=' . Cpanel::Encoder::URI::uri_encode_str($app),

        #
        # TODO: Add a way for $LANG{''} in 'name' to be translated.
        # This is currently a known deficiency in the DynamicUI system
        #
        name => sprintf( q<$LANG{'%s'}>, $link_data->{'label'} || $app ),
    );

    if ( $link_data->{'hide'} ) {
        $link_obj_params{'if'} = '0';
    }

    return $dynamic_ui->link2dui( Cpanel::Themes::Assets::Link->new(%link_obj_params) );
}

sub _run_creation_queue {
    my ($to_create) = @_;
    my $todo = Cpanel::CommandQueue->new();
    for my $create_data (@$to_create) {
        $todo->add(
            sub { Cpanel::FileUtils::Write::overwrite(@$create_data) },
            sub { Cpanel::Autodie::unlink( $create_data->[0] ) },
            "unlink $create_data->[0]",
        );
    }

    $todo->run();

    return 1;
}

sub _validate_user_app {
    my ( $user, $app ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($user);
    Cpanel::Validate::FilesystemNodeName::validate_or_die($app);

    # Note: groups always need to start with group_ for legacy compatibility
    if ( $app =~ m{^\Q$Cpanel::Integration::Config::GROUP_PREFIX\E} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument cannot begin with “[_2]”.', [ 'app', $Cpanel::Integration::Config::GROUP_PREFIX ] );
    }

    return 1;
}

sub _validate_user_groupid {
    my ( $user, $group_id ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($user);
    Cpanel::Validate::FilesystemNodeName::validate_or_die($group_id);

    # Internally, groups are stored with the “group_” prefix for legacy compatibility
    #
    # The below prevents them from shooting themselves in the foot and creating a group
    # called:
    # group_group_NAME
    if ( $group_id =~ m{^\Q$Cpanel::Integration::Config::GROUP_PREFIX\E} ) {    # We always add this for them
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument cannot begin with “[_2]”.', [ 'group_id', $Cpanel::Integration::Config::GROUP_PREFIX ] );
    }

    return 1;
}

sub _validate_data_and_remove_unknown_items {
    my ( $link_data, $known_keys ) = @_;

    for my $key ( keys %$link_data ) {
        if ( !grep { $_ eq $key } @{$known_keys} ) {
            warn "Ignoring unrecognized data key “$key” ($link_data->{$key})!";
            delete $link_data->{$key};
        }

        if ( ref $link_data->{$key} ) {

            #Since we don’t expose a way of sending data structures via the API,
            #this exception can be a simple one.
            die "“$key” ($link_data->{$key}) must not be a reference!";
        }
    }

    if ( $link_data->{'label'} && -1 != index( $link_data->{'label'}, q<'> ) ) {
        die Cpanel::Exception::create( 'InvalidCharacters', 'The parameter “[_1]” may not contain single-quote characters (apos()).', ['label'] );
    }
}

1;
