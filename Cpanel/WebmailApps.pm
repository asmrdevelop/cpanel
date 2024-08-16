package Cpanel::WebmailApps;

# cpanel - Cpanel/WebmailApps.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Conf              ();
use Cpanel::Parser::FeatureIf ();
require Cpanel::DataStore;

sub get_default_webmail_apps_ar {
    my ($theme) = @_;
    my $cpanel_conf;
    $cpanel_conf = Cpanel::Conf->new();

    $theme ||= $cpanel_conf->default_webmail_theme;

    my @default_webmail_apps_ar = ();

    # please do not use a Cpanel::RPM::Versions::File object here !

    push @default_webmail_apps_ar,
      {
        'url'         => '/3rdparty/roundcube/index.php',
        'id'          => 'roundcube',
        'if'          => '!$CONF{\'skiproundcube\'}',
        'displayname' => 'Roundcube',
        'icon'        => '/webmail/' . $theme . '/images/roundcube_logo.png',
      };

    return \@default_webmail_apps_ar;
}

sub api2_listwebmailapps {
    my ($no_append_token) = @_;
    my $webmail_dir = '/var/cpanel/webmail';

    my $webmail_apps = Cpanel::DataStore::load_ref("$webmail_dir/webmail.yaml") || get_default_webmail_apps_ar( $Cpanel::CPDATA{'RS'} );

    if ( opendir my $webmail_dir_fh, $webmail_dir ) {
        while ( my $wm_file = readdir($webmail_dir_fh) ) {
            my ($appid) = $wm_file =~ m/^webmail_([a-zA-Z0-9-]+)\.yaml$/;
            if ($appid) {
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
          if ( defined $wm_app->{'if'} && !Cpanel::Parser::FeatureIf::ifresult( $wm_app->{'if'} ) )
          || ( defined $wm_app->{'feature'} && !Cpanel::Parser::FeatureIf::featureresult( $wm_app->{'feature'} ) )
          || !defined $wm_app->{'url'}
          || !defined $wm_app->{'displayname'}
          || !defined $wm_app->{'icon'}
          || !defined $wm_app->{'id'};

        $wm_app->{'url'} = $ENV{'cp_security_token'} . $wm_app->{'url'} unless $no_append_token;
        push @wm_res, $wm_app;
    }

    @wm_res = sort( { $a->{'id'} cmp $b->{'id'} } @wm_res );

    return \@wm_res;
}

our %API = (
    listwebmailapps => { needs_role => 'Webmail', allow_demo => 1 },
);

sub api2 {
    my ($func) = @_;
    return { worker_node_type => 'Mail', %{ $API{$func} } } if $API{$func};
    return;
}

1;
