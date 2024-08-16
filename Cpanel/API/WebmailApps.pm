package Cpanel::API::WebmailApps;

# cpanel - Cpanel/API/WebmailApps.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Conf       ();
use Cpanel::LoadModule ();

our %API = (
    _worker_node_type => 'Mail',
    _needs_role       => 'MailReceive',
    list_webmail_apps => { allow_demo => 1 },
);

sub _get_default_webmail_apps_ar {
    my ($theme) = @_;

    my ( $cpanel_conf, $webmail_default_theme );
    $cpanel_conf           = Cpanel::Conf->new();
    $webmail_default_theme = $cpanel_conf->default_webmail_theme;

    $theme ||= $webmail_default_theme;

    my $icons = {
        'roundcube' => 'roundcube.png',
    };

    my $display_names = {
        'roundcube' => 'Roundcube',
    };

    my @default_webmail_apps_ar = ();
    foreach my $app (qw/roundcube/) {
        my $skip_check = 'skip' . $app;

        next unless -e '/usr/local/cpanel/base/3rdparty/' . $app . '/index.php';
        push @default_webmail_apps_ar,
          {
            'url'         => '/3rdparty/' . $app . '/index.php',
            'id'          => $app,
            'feature'     => $app,
            'enabled'     => $Cpanel::CONF{$skip_check} ? 0 : 1,
            'displayname' => $display_names->{$app},
            'icon'        => '/webmail/' . $theme . '/images/' . $icons->{$app},
          };
    }

    return \@default_webmail_apps_ar;
}

sub _get_webmail_dir {
    return '/var/cpanel/webmail';
}

sub list_webmail_apps {
    my ( $args, $result ) = @_;
    my (
        $theme    # name of the theme
    ) = $args->get(qw( theme ));

    my $webmail_dir = _get_webmail_dir();
    my $webmail_apps;
    if ( -e "$webmail_dir/webmail.yaml" ) {

        # CPANEL-16465: we cannot use Cpanel::CachedDataStore because we are not able
        # to lock the .yaml for reaching since we do not own the directory
        Cpanel::LoadModule::load_perl_module('Cpanel::DataStore') if !$INC{'Cpanel/DataStore.pm'};
        $webmail_apps = Cpanel::DataStore::load_ref("$webmail_dir/webmail.yaml");
    }
    $webmail_apps ||= _get_default_webmail_apps_ar($theme);

    if ( opendir my $webmail_dir_fh, $webmail_dir ) {
        while ( my $wm_file = readdir($webmail_dir_fh) ) {
            my ($appid) = $wm_file =~ m/^webmail_([a-zA-Z0-9-]+)\.yaml$/;
            if ($appid) {

                # CPANEL-16465: we cannot use Cpanel::CachedDataStore because we are not able
                # to lock the .yaml for reaching since we do not own the directory
                Cpanel::LoadModule::load_perl_module('Cpanel::DataStore') if !$INC{'Cpanel/DataStore.pm'};
                my $app_obj = Cpanel::DataStore::load_ref("$webmail_dir/$wm_file");

                if ( ref $app_obj eq 'HASH' && exists $app_obj->{'displayname'} ) {
                    $app_obj->{'id'} = $appid;
                    push @{$webmail_apps}, $app_obj;
                }
            }
        }
        closedir $webmail_dir_fh;
    }

    my @wm_res;
    foreach my $wm_app ( @{$webmail_apps} ) {
        next
          if ( defined $wm_app->{'enabled'} && !( $wm_app->{'enabled'} ) )
          || ( defined $wm_app->{'feature'} && !main::hasfeature( $wm_app->{'feature'} ) )
          || !defined $wm_app->{'url'}
          || !defined $wm_app->{'displayname'}
          || !defined $wm_app->{'icon'}
          || !defined $wm_app->{'id'};

        $wm_app->{'url'} = $ENV{'cp_security_token'} . $wm_app->{'url'} if defined $ENV{'cp_security_token'};

        delete $wm_app->{'enabled'} if ( defined $wm_app->{'enabled'} );
        delete $wm_app->{'feature'} if ( defined $wm_app->{'feature'} );

        push @wm_res, $wm_app;
    }

    @wm_res = sort( { ( defined( $a->{'weight'} ) && defined( $b->{'weight'} ) ) ? $a->{'weight'} <=> $b->{'weight'} : $a->{'id'} cmp $b->{'id'} } @wm_res );

    $result->data( \@wm_res );

    return 1;
}

1;
