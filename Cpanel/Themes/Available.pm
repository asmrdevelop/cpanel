package Cpanel::Themes::Available;

# cpanel - Cpanel/Themes/Available.pm                Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Server::Type ();
use Cpanel::Themes::Get  ();

=encoding utf-8

=head1 NAME

Cpanel::Themes::Available - Get a list of available themes.

=head1 SYNOPSIS

    use Cpanel::Themes::Available;

    my @all_installed_themes = Cpanel::Themes::Available::getthemeslist();
    my @available_themes = Cpanel::Themes::Available::get_available_themes();
    my $y_n = Cpanel::Themes::Available::is_theme_available($theme);

=cut

our $VERSION = '1.2';

my %ok_themes;

my $THEMES_BASE             = '/usr/local/cpanel/base/frontend';
my $CUSTOM_THEMES_LIST_FILE = '/var/cpanel/themes.conf';

=head2 getthemeslist()

Return a list of themes as it exists in /usr/local/cpanel/base/frontend

=cut

sub getthemeslist {
    my @THEMES;
    _init_ok_themes() if !scalar %ok_themes;
    if ( opendir my $theme_dh, $THEMES_BASE ) {
        while ( my $fs = readdir $theme_dh ) {
            if ( $ok_themes{$fs} ) {
                push @THEMES, $fs;
            }
            else {
                next if index( $fs, '.' ) == 0;
                next if Cpanel::Themes::Get::theme_has_reached_eol($fs);
                next if ( $fs =~ m/\.(?:jpg|gif|png|html)$/ );
                if ( -d "$THEMES_BASE/$fs" ) {
                    push @THEMES, $fs;
                }
            }
        }
        closedir $theme_dh;
        my @sorted_themes = sort @THEMES;
        return @sorted_themes;
    }
    else {

        # Should never happen so warn here won't be seen except on very broken systems
        warn "Unable to read $THEMES_BASE: $!" if !Cpanel::Server::Type::is_dnsonly();
        return;
    }
}

=head2 get_available_themes()

Return a list of themes that are available for use on the system.

=cut

# this method is used for overriding the list of themes as displayed to resellers in x3
# if we ever implement access restriction for themes, we'll proably want to add a user param here.
sub get_available_themes {
    my @themes;

    if ( -e $CUSTOM_THEMES_LIST_FILE ) {
        if ( open my $themeconf_fh, '<', $CUSTOM_THEMES_LIST_FILE ) {
            while ( my $line = readline $themeconf_fh ) {
                chomp $line;
                next if !$line;
                push @themes, $line;
            }
            close $themeconf_fh;

            @themes = sort @themes;
        }
        else {

            #Uh-oh!
            warn "$CUSTOM_THEMES_LIST_FILE exists but cannot be opened: $!";
            return;
        }
    }
    else {
        @themes = getthemeslist();
        return if !@themes;
    }

    return \@themes;
}

=head2 get_available_themes($theme)

Returns boolean int indicating whether a theme is available for use or not.

=cut

sub is_theme_available {
    my ($theme) = @_;
    return int grep { $_ eq $theme } @{ get_available_themes() };
}

sub _init_ok_themes {
    my @ok_themes_array = Cpanel::Themes::Get::get_list();
    @ok_themes{@ok_themes_array} = (1) x scalar(@ok_themes_array);
    return 1;
}

1;
