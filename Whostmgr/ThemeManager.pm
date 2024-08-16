package Whostmgr::ThemeManager;

# cpanel - Whostmgr/ThemeManager.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::App    ();
use Cpanel::Logger ();

our $NO_LINKS = 1;
our %APPS     = (
    'login' => {
        'path'           => '/usr/local/cpanel/base/unprotected',
        'themelistfunc'  => \&_fetchloginthemes,
        'themecheckfile' => 'header.html',
        'image'          => 'auth.gif',
        'imgdescription' => sub { return _locale()->maketext("Badge icon") },
        'name'           => 'Login',
        'immutable'      => [ 'mobile', 'cpanel', 'cpanel-legacy' ],
    },
    'cpanel' => {
        'path'           => '/usr/local/cpanel/base/frontend',
        'themelistfunc'  => \&_fetchcpanelthemes,
        'themecheckfile' => 'index.html',
        'image'          => 'cpanel.png',
        'imgdescription' => sub { return _locale()->maketext("cPanel Logo") },
        'name'           => 'cPanel',
        'immutable'      => [ 'x', 'x2', 'x3', 'x3mail', 'paper_lantern', 'jupiter' ],
    },
    'webmail' => {
        'path'           => '/usr/local/cpanel/base/webmail',
        'themelistfunc'  => \&_fetchcpanelthemes,
        'themecheckfile' => 'index.html',
        'image'          => 'webemail.gif',
        'imgdescription' => sub { return _locale()->maketext("Globe and letter icon for mail") },
        'name'           => 'Webmail',
        'immutable'      => [ 'x', 'x2', 'x3', 'x3mail', 'paper_lantern', 'jupiter' ],
    },
);

my $_lh;

sub _locale {
    return $_lh ||= do {
        require Cpanel::Locale;
        Cpanel::Locale->get_handle();
    };
}

sub _fetchloginthemes {
    return _fetchthemes_for(
        links => shift,
        dir   => $APPS{'login'}->{'path'},
        rules => sub {
            my ( $links, $dir, $theme ) = @_;
            return if $theme =~ /^lisc$/;
            return if ( $theme eq 'images' || $theme eq 'css' );
            return if !-r "$dir/$theme/login.tmpl" && !-r "$dir/$theme/header.html";
            1;
        },
        error_msg => 'No login themes located.'
    );
}

sub _fetchcpanelthemes {
    local $Cpanel::App::appname = 'cpaneld';
    return _fetchthemes_for(
        links => shift,
        dir   => $APPS{'cpanel'}->{'path'},
        rules => sub {
            my ( $links, $dir, $theme ) = @_;
            return                      if !-d $dir . '/' . $theme;
            require Cpanel::Themes::Get if !$INC{'Cpanel/Themes/Get.pm'};
            return                      if !Cpanel::Themes::Get::is_usable_theme($theme);

            1;
        },
        error_msg => 'No cPanel themes located..'
    );
}

# common rules and mechanism to check a theme
sub _fetchthemes_for {
    my (%opts) = @_;

    my $links = $opts{links};
    my $dir   = $opts{dir};
    my @THEMES;
    if ( opendir my $themes_dh, $dir ) {
        my @files = readdir $themes_dh;
        closedir $themes_dh;
        foreach my $theme (@files) {
            if ( !$theme ) {
                Cpanel::Logger::logger( { 'message' => 'Bad theme directory lookup (possible rootkit installed)', 'level' => 'warn', 'service' => 'whostmgr', 'output' => 0, 'backtrace' => 1, } );
                next;
            }

            # common rules ( factorized here at this step )
            next if $theme =~ m/^\./;
            next if ( defined $links && $links == $NO_LINKS && -l "$dir/$theme" );

            # check extra rules
            next if ( defined $opts{rules} && !$opts{rules}( $links, $dir, $theme ) );
            push @THEMES, $theme;
        }
    }
    else {
        warn "Unable to open directory $dir: $!";
    }
    return @THEMES;
}

1;
