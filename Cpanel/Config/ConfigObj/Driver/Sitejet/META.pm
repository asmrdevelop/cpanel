package Cpanel::Config::ConfigObj::Driver::Sitejet::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/Sitejet/META.pm
#                                      Copyright 2024 WebPros International, LLC
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Config::ConfigObj::Driver::Sitejet::META

=head1 DESCRIPTION

Feature Showcase metadata for Sitejet

=cut

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);

our $VERSION = "2.0";

=head1 FUNCTIONS

=head2 translate

Returns the string. Provides the string to the locale tool.

=cut

sub translate ($string) { return $string; }

=head2 get_driver_name()

Returns the driver name. This name is used as the filename for the touchfile
put in the C</var/cpanel/activate/features/> directory.

=cut

use constant get_driver_name => 'sitejet_builder_campaign_03_2024';
use constant options => (
    [ "Keep"          => translate("Keep current settings.") ],
    [ "EnableAll"     => translate("Enable for all feature lists.") ],
    [ "EnableDefault" => translate("Enable for the default feature list.") ],
);

my $short        = translate('Sitejet is now available in cPanel & WHM!');
my $long         = translate('Sitejet is now available in cPanel & WHM!');
my $version_text = translate("We disable Sitejet by default on version 110.");

=head2 content

Defines the content used in the Feature Showcase entry

=cut

sub content ($locale) {
    my $current_setting = "Keep";

    my $abstract = translate(
        join(
            "",
            "Sitejet offers a modern website builder for cPanel users. Sitejet provides a variety of customizable templates and a drag-and-drop interface. ",
            "This feature makes it easy for users of all skill levels to create stunning websites quickly. Empower your users with Sitejet for simple, powerful website development.",
        )
    );

    if ($locale) {
        $short    = $locale->makevar($short);
        $long     = $locale->makevar($long);
        $abstract = "<p>" . $locale->makevar($abstract) . "</p>\n";
        if ( is_110() ) {
            $abstract .= "$version_text\n";
            foreach my $option_ar (options) {
                my $option_text = $locale->makevar( $option_ar->[1] );
                $abstract .= qq{<p><label style="width:auto"><input type="radio" value="$option_ar->[0]" name="sitejet_enable_disable"} . ( $option_ar->[0] eq $current_setting ? ' checked' : '' ) . "> $option_text " . "</label></p>\n";
            }
        }
    }
    else {
        $abstract = "<p>" . $abstract . "</p>\n";
        if ( is_110() ) {
            $abstract .= "$version_text\n";
            foreach my $option_ar (options) {
                $abstract .= qq{<p><label style="width:auto"><input type="radio" value="$option_ar->[0]" name="sitejet_enable_disable"} . ( $option_ar->[0] eq $current_setting ? ' checked' : '' ) . "> $option_ar->[1] " . "</label></p>\n";
            }
        }
    }

    return {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/sitejet-builder',
        'name'   => {
            'short'  => $short,
            'long'   => $long,
            'driver' => get_driver_name(),
        },
        'first_appears_in' => '110',
        'version'          => $Cpanel::Config::ConfigObj::Driver::Sitejet::META::VERSION,
        'readonly'         => 1,
        'abstract'         => $abstract,
    };
}

=head2 showcase()

Determine how and if an item should appear in the showcase

=cut

sub showcase {
    return { 'is_recommended' => 0, 'is_spotlight_feature' => 1 };
}

=head2 is_110()

Returns true if cPanel version is 110.

=cut

sub is_110 {
    require Cpanel::Version;
    require Cpanel::Version::Compare;

    my $version = Cpanel::Version::getversionnumber();
    return Cpanel::Version::Compare::compare_major_release( $version, '<=', '11.110' );
}

1;
