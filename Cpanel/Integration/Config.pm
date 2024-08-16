package Cpanel::Integration::Config;

# cpanel - Cpanel/Integration/Config.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $GROUP_PREFIX             = 'group_';
our $INTEGRATION_BASE_DIR     = '/var/cpanel/integration';
our $USER_CONFIG_FILE_SUFFIX  = 'userconfig';
our $ADMIN_CONFIG_FILE_SUFFIX = 'adminconfig';
our $USER_CONFIG_PERMS        = 0644;                        # Protected by the dir perms
our $ADMIN_CONFIG_PERMS       = 0600;

use Cpanel::Context                      ();
use Cpanel::Exception                    ();
use Cpanel::FileUtils::Dir               ();
use Cpanel::Validate::FilesystemNodeName ();

my $BASE_DIR_PERMS = 0751;
my $USER_DIR_PERMS = 0750;

sub _DYNAMICUI_BASE_DIR {
    return "$INTEGRATION_BASE_DIR/dynamicui";
}

sub _LINKS_BASE_DIR {
    return "$INTEGRATION_BASE_DIR/links";
}

sub dynamicui_dir_for_user {
    my ($user) = @_;
    Cpanel::Validate::FilesystemNodeName::validate_or_die($user);
    return _DYNAMICUI_BASE_DIR() . "/$user";
}

sub links_dir_for_user {
    my ($user) = @_;
    Cpanel::Validate::FilesystemNodeName::validate_or_die($user);
    return _LINKS_BASE_DIR() . "/$user";
}

sub get_dynamicui_path_for_user_group {
    my ( $user, $group ) = @_;
    return get_dynamicui_path_for_user_app( $user, $GROUP_PREFIX . $group );
}

sub get_dynamicui_path_for_user_app {
    my ( $user, $app ) = @_;

    _ensure_dynamicui_setup_for_user($user) if $> == 0;

    my $dynamicui_dir = dynamicui_dir_for_user($user);

    Cpanel::Validate::FilesystemNodeName::validate_or_die($app);

    return "$dynamicui_dir/dynamicui_$app.conf";
}

sub get_app_links_for_user {
    my ($user) = @_;

    Cpanel::Context::must_be_list();

    my $links_dir = links_dir_for_user($user);

    return if !-e $links_dir;

    return map {
        my $app = $_;
        index( $app, $GROUP_PREFIX ) != 0 && $app =~ s{\.\Q$USER_CONFIG_FILE_SUFFIX\E$}{} ? $app : ()
    } @{ Cpanel::FileUtils::Dir::get_directory_nodes($links_dir) };
}

sub get_groups_for_user {
    my ($user) = @_;

    Cpanel::Context::must_be_list();

    my $links_dir = links_dir_for_user($user);

    return if !-e $links_dir;

    return map {
        my $group = $_;
        $group =~ s{^\Q$GROUP_PREFIX\E}{} && $group =~ s{\.\Q$USER_CONFIG_FILE_SUFFIX\E$}{} ? $group : ()
    } @{ Cpanel::FileUtils::Dir::get_directory_nodes($links_dir) };
}

sub get_user_group_config_path {
    my ( $user, $group ) = @_;
    return _get_app_config_path( $user, $GROUP_PREFIX . $group, $USER_CONFIG_FILE_SUFFIX );
}

sub get_app_config_path_for_user {
    my ( $user, $app ) = @_;
    return _get_app_config_path( $user, $app, $USER_CONFIG_FILE_SUFFIX );
}

sub get_app_config_path_for_admin {
    my ( $user, $app ) = @_;
    return _get_app_config_path( $user, $app, $ADMIN_CONFIG_FILE_SUFFIX );
}

sub _ensure_dynamicui_setup_for_user {
    my ($user) = @_;
    return _ensure_integration_setup_for_user( 'dynamicui', $user );
}

sub _ensure_links_setup_for_user {
    my ($user) = @_;
    return _ensure_integration_setup_for_user( 'links', $user );
}

sub _ensure_integration_setup_for_user {
    my ( $type, $user ) = @_;

    my %setups = (
        'dynamicui' => {
            'base_dir'           => _DYNAMICUI_BASE_DIR(),
            'user_base_dir_func' => \&dynamicui_dir_for_user,
        },
        'links' => {
            'base_dir'           => _LINKS_BASE_DIR(),
            'user_base_dir_func' => \&links_dir_for_user,
        },
    );

    if ( !$setups{$type} ) {
        die "Implementer error: $type is not known to _ensure_integration_setup_for_user";
    }

    my $base_dir = $setups{$type}->{'base_dir'};
    my $user_dir = $setups{$type}->{'user_base_dir_func'}->($user);
    my $current_gid;

    require Cpanel::PwCache::Get;
    my $expected_gid = Cpanel::PwCache::Get::getgid($user);
    if ( !defined $expected_gid ) {
        die Cpanel::Exception::create( 'UserNotFound', [ name => $user ] );
    }

    if ( !defined( $current_gid = ( stat($user_dir) )[2] ) ) {
        require Cpanel::Mkdir;
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $INTEGRATION_BASE_DIR, $BASE_DIR_PERMS );
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $base_dir,             $BASE_DIR_PERMS );
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $user_dir,             $USER_DIR_PERMS );
        $current_gid = ( stat($user_dir) )[2];
    }
    if ( $current_gid != $expected_gid ) {
        require Cpanel::Autodie;
        Cpanel::Autodie::chown( 0, $expected_gid, $user_dir );

    }
    return 1;
}

sub _get_app_config_path {
    my ( $user, $app, $suffix ) = @_;

    _ensure_links_setup_for_user($user) if $> == 0;

    my $links_dir = links_dir_for_user($user);

    Cpanel::Validate::FilesystemNodeName::validate_or_die($app);

    return "$links_dir/$app.$suffix";
}

1;
