package Cpanel::Themes::Get;

# cpanel - Cpanel/Themes/Get.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles       ();
use Cpanel::App               ();
use Cpanel::Config::Constants ();

our @THEME_FILE_EXT_SORT_ORDER = (qw(php cpphp phpcp html htm html.tt));
our %EOL_THEMES                = (
    NO            => 1,
    Y             => 1,
    YES           => 1,
    advanced      => 1,
    default       => 1,
    iconic        => 1,
    mailonly      => 1,
    tree          => 1,
    y             => 1,
    x2            => 1,
    x             => 1,
    x3            => 1,
    x3mail        => 1,
    x4            => 1,
    x4mail        => 1,
    xmail         => 1,
    bluelagoon    => 1,
    monsoon       => 1,
    Xskin         => 1,
    n             => 1,
    no            => 1,
    tree          => 1,
    gorgo         => 1,
    paper_lantern => 1
);

# Note, this feeds Cpanel::Update::Now
our %CPANEL_DISTRIBUTED_THEMES = (
    cpanel_default_theme() => 1,
);

# Note, this feeds Cpanel::Update::Now
sub get_list {
    return reverse sort keys %Cpanel::Themes::Get::CPANEL_DISTRIBUTED_THEMES;
}

sub theme_has_reached_eol {
    my ($theme) = @_;
    return $EOL_THEMES{$theme} ? 1 : 0;
}

sub is_usable_theme {
    my ($theme) = @_;
    return 0 if !$theme;
    return 1 if $CPANEL_DISTRIBUTED_THEMES{$theme};
    return 0 if $theme =~ m{\.\.} || $theme =~ m{/} || $theme =~ m{[\r\n]};

    return 0 if theme_has_reached_eol($theme);
    return get_theme_entry_url($theme) ? 1 : 0;
}

sub get_theme_entry_url {
    my ( $theme, $appname ) = @_;

    $appname ||= $Cpanel::App::appname || $Cpanel::appname || 'cpaneld';

    my $basedir = $appname =~ m{^webmail} ? 'webmail' : 'frontend';

    my $basepath = "$Cpanel::ConfigFiles::CPANEL_ROOT/base/$basedir";

    foreach my $ext (@THEME_FILE_EXT_SORT_ORDER) {
        if ( -e "$basepath/$theme/index.$ext" ) {
            return "/$basedir/$theme/index.$ext";
        }
    }

    return;

}

sub webmail_default_theme {
    require Cpanel::Conf;

    # $webmail_default_theme will be used as default fallback
    # theme for Webmail user interface
    return Cpanel::Conf->new()->default_webmail_theme;
}

sub cpanel_default_theme {
    return $Cpanel::Config::Constants::DEFAULT_CPANEL_THEME;
}

1;
