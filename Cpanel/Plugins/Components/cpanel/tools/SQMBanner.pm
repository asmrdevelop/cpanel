package Cpanel::Plugins::Components::cpanel::tools::SQMBanner;

use Moo;
use cPstrict;

use Cpanel::Imports;

extends 'Cpanel::Plugins::Components::SQMBannerBase';

has '+feature_flag' => (
    default => 'cpanel-tools-sidebar.banner-cpanel.koality.plugin-banner.removed',
);

has '+js_url' => (
    default => 'plugin_banners/koality/sqm-sidebar-app/dist/cp-koality-sidebar.cmb.min.js',
);

has '+slot' => (
    default => 'page-bottom',
);

has '+process' => (
    default => sub { \1 },
);

has '+markup' => (
    default => sub {
        require Cpanel::Encoder::Tiny;
        my $body_title   = Cpanel::Encoder::Tiny::safe_html_encode_str( locale()->maketext("Site Quality Monitoring") );
        my $body_text    = Cpanel::Encoder::Tiny::safe_html_encode_str( locale()->maketext("We’ll watch your site for you!") );
        my $button_label = Cpanel::Encoder::Tiny::safe_html_encode_str( locale()->maketext("Start Monitoring") );
        my $close_title  = Cpanel::Encoder::Tiny::safe_html_encode_str( locale()->maketext("Close") );

        return <<"END_TEMPLATE";
        <script id="cp-koality-sidebar-app-template" type="text/html">
            <cp-koality-sidebar-app
                bodyTitle="$body_title"
                bodyText="$body_text"
                closeTitle="$close_title"
                buttonLabel="$button_label">
            </cp-koality-sidebar-app>
        </script>
END_TEMPLATE
    }
);

# Only show the banner if it is enabled AND they do not already have a SQM account.
around 'is_enabled' => sub ( $orig, @args ) {

    my $is_enabled = $orig->(@args);
    return 0 if !$is_enabled;

    require Cpanel::Koality::User;
    my $user = Cpanel::Koality::User->new();
    return $user->app_token ? 0 : 1;
};

1;
