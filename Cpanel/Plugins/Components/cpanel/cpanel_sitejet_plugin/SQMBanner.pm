package Cpanel::Plugins::Components::cpanel::cpanel_sitejet_plugin::SQMBanner;

use Moo;
use cPstrict;

extends 'Cpanel::Plugins::Components::SQMBannerBase';

has '+feature_flag' => (
    is      => 'ro',
    default => 'cpanel-sitejet.banner-cpanel.koality.plugin-banner.removed',
);

has "+markup" => (
    is      => 'ro',
    default => '<cp-koality-banner></cp-koality-banner>',
);

has '+js_url' => (
    is      => 'ro',
    default => 'plugin_banners/koality/sqm-banner/cp-koality-banner.js',
);

has '+slot' => (
    is      => 'ro',
    default => 'content-end',
);

1;
