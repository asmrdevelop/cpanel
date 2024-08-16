package Whostmgr::Customization::Utils;

# cpanel - Whostmgr/Customization/Utils.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Whostmgr::Customization::Utils - Utility functions to help with customization.

=head1 SYNOPSIS

    use Whostmgr::Customization::Utils ();

=cut

use strict;
use warnings;

=head1 METHODS

=cut

=head2 hex2rgb

Convert hex colors to rgbs.

=head3 Arguments

=over 4

=item hex

Color coded in hex.

=back

=head3 Returns

List that contains red, green, and blue color values.

=cut

sub hex2rgb {
    my ($hex) = @_;
    $hex =~ s/^\#//;

    return map { $_ } unpack 'C*', pack 'H*', $hex;
}

=head2 luminance ($RED, $GREEN, $BLUE)

Caculate luminance for colors according to W3C/WCAG wiki for the 'official'
luminance formula https://www.w3.org/WAI/GL/wiki/Relative_luminance.

=head3 Arguments

=over 4

=item rgb

Array of color values in rgb.

=back

=head3 Returns

Relative luminance for the color.

=cut

sub luminance {
    my (@rgb) = @_;
    my @vals = map { my $v = $_ / 255; $v <= 0.03928 ? $v / 12.92 : _pow( ( $v + 0.055 ) / 1.055, 2.4 ) } @rgb;

    return $vals[0] * 0.2126 + $vals[1] * 0.7152 + $vals[2] * 0.0722;
}

sub _pow {
    my ( $v, $e ) = @_;

    return exp( $e * log($v) );
}

=head2 contrast ($RGB1, $RGB2)

Calculates the contrast of two colors in rgbs.

=over

=item $RGB1

A decimal color code formatted as an array reference of three integers (0-255)

=item $RGB2

A decimal color code formatted as an array reference of three integers (0-255), to be compared to the first.
The order these two parameters are passed in does not matter.

=back

=head3 RETURNS

A floating point value representing a ratio between the darkest and lightest color.

=cut

sub contrast {
    my ( $rgb1, $rgb2 ) = @_;

    my $lum1      = luminance( $rgb1->[0], $rgb1->[1], $rgb1->[2] );
    my $lum2      = luminance( $rgb2->[0], $rgb2->[1], $rgb2->[2] );
    my $brightest = $lum1 > $lum2 ? $lum1 : $lum2;
    my $darkest   = $lum1 > $lum2 ? $lum2 : $lum1;

    return ( $brightest + 0.05 ) / ( $darkest + 0.05 );
}

=head2 get_favorites(TOOLS)

Fetch the favorites from NVData, parse, and convert into an array of usable objects

=head3 ARGUMENTS

=over

=item TOOLS - ARRAYREF

The list of tools available to the current logged in user.

=back

=head3 RETURNS

ARRAYREF - A list that contains all favorited applications or undef if the user
has not selected any favorites.

=cut

sub get_favorites {
    my ($tools) = @_;
    require Whostmgr::NVData;
    my $favorites_nvdata = Whostmgr::NVData::get('favorites');
    my @favorites;
    my $plugins;

    if ( ref $favorites_nvdata eq 'ARRAY' ) {
        my %groups = map { ( $_->{key} => $_->{items} ) } @{ $tools->{groups} };

        foreach my $identifier (@$favorites_nvdata) {
            my ( $group, $key ) = split /\$/, $identifier;
            my $app = undef;
            if ( $group eq 'plugins' ) {
                if ( !$plugins ) {
                    require Cpanel::Plugins::DynamicUI;
                    $plugins = Cpanel::Plugins::DynamicUI::get();
                }
                ($app) = grep { $key eq $_->{uniquekey} } @$plugins;

                # Plugin is in user's favorites list, but plugin is no longer installed
                next if !$app;

                $app->{'group'}       = $group;
                $app->{'type'}        = 'plugin';
                $app->{'key'}         = $app->{'uniquekey'};
                $app->{'description'} = '';
                $app->{'itemdesc'}    = $app->{'showname'};
                $app->{'url'}         = '/cgi/' . $app->{'cgi'};
            }
            else {
                my $group_items = $groups{$group};
                ($app) = grep { $key eq $_->{key} } @$group_items;

                # App is in user's favorites list, but app doesn't exist
                next if !$app;

                $app->{'type'} = 'builtin';
            }

            $app->{'description'} =~ s/\&amp\;/\&/;

            push @favorites, $app;
        }

        return \@favorites;
    }

    return;
}

1;
