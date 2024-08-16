package Cpanel::Themes;

# cpanel - Cpanel/Themes.pm                          Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug                      ();
use Cpanel::Config::LoadCpUserFile     ();
use Cpanel::LoadModule                 ();
use Cpanel::Themes::Available          ();
use Cpanel::Themes::Utils              ();
use Cpanel::Exception                  ();
use Cpanel::AcctUtils::Lookup          ();
use Cpanel::AcctUtils::Lookup::Webmail ();

our $VERSION = '1.2';

our %API = (
    get_available_themes => { allow_demo => 1 },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

*api2_get_available_themes = *Cpanel::Themes::Available::get_available_themes;

sub get_users_links {
    my ( $user, $service ) = @_;

    $service ||= 'cpaneld';

    # get the user's theme
    my $is_webmail_user = ( $service =~ m{webmail}i || Cpanel::AcctUtils::Lookup::Webmail::is_strict_webmail_user($user) ) ? 1 : 0;
    my $theme           = get_user_theme($user);
    my $theme_path      = $is_webmail_user ? Cpanel::Themes::Utils::get_webmail_theme_root($theme) : Cpanel::Themes::Utils::get_cpanel_theme_root($theme);
    my $base_url        = $theme_path;
    substr( $base_url, 0, length '/usr/local/cpanel/base/', '' );
    my $format = $is_webmail_user ? 'JSON' : 'DynamicUI';

    Cpanel::LoadModule::load_perl_module('Cpanel::Themes::SiteMap');
    my $theme_obj = Cpanel::Themes::SiteMap->new( 'path' => $theme_path, 'user' => $user, 'format' => $format );

    if ( $theme_obj->load() ) {
        my $links_ar = $is_webmail_user ? $theme_obj->{'serializer_obj'}->{'extras'}->[0]->{'items'} : $theme_obj->{'serializer_obj'}->{'links'};
        my %link_map = map { $_->{'implements'} => "$base_url" . ( $_->{'uri'} || $_->{'url'} ) } grep { defined $_->{'implements'} } @{$links_ar};
        return \%link_map;
    }

    Cpanel::Debug::log_warn("The system could not load the SiteMap for the “$service” service with user “$user”: This user’s links will not be available");
    return {};
}

sub get_user_theme {
    my ($user) = @_;

    my $system_user  = Cpanel::AcctUtils::Lookup::get_system_user($user);
    my $user_file_hr = Cpanel::Config::LoadCpUserFile::load($system_user);

    unless ( keys %{$user_file_hr} ) {
        die Cpanel::Exception::create( 'UserNotFound', [ 'name' => $user ] );
    }

    return $user_file_hr->{'RS'};
}

sub get_user_link_for_app {
    my ( $user, $app, $service ) = @_;

    return get_users_links( $user, $service )->{$app};
}

1;
