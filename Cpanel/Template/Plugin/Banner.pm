package Cpanel::Template::Plugin::Banner;

# cpanel - Cpanel/Template/Plugin/Banner.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::Banner - banner add helper methods.

=head1 DESCRIPTION

Plugin to support banner ads in the product.

=head1 SYNOPSIS

USE Banner;


=cut

use parent 'Cpanel::Template::Plugin::BaseDefault';

use Cpanel::LoadModule         ();
use Cpanel::LoadModule::Custom ();

use constant ULC => '/usr/local/cpanel';

=head1 CONSTRUCTORS

ADAPTED FROM Template::Plugin DOCUMENTATION

=head2 CLASS->new(CONTEXT)

Initialize the plugin from the context.

=cut

sub new {
    my ( $class, $context ) = @_;

    return bless {
        '_CONTEXT' => $context,
    }, $class;
}

=head1 PRIVATE METHODS

=head2 _has_license_flag(flag)

Check if the requrested license flag is set.

=cut

sub _has_license_flag {
    my ($flag) = @_;
    require Cpanel::License::Flags;
    return Cpanel::License::Flags::has_flag($flag);
}

=head2 _calculate_banner_paths(APP, THEME)

Determin the path to the banners folders for the current application and theme.

=head3 ARGUMENTS

=over

=item APP - string

One of whm, cpanel, webmail

=item THEME - string

The cpanel or webmail theme. For whm it is ignored.

=back

=head3 RETURNS

string - the path to the banners folder.

=cut

sub _calculate_banner_paths ( $app, $theme ) {
    if ( $app eq 'whm' ) {
        return ULC . "/whostmgr/docroot/templates/banners";
    }
    elsif ( $app eq 'cpanel' ) {
        return ULC . "/base/frontend/$theme/banners";
    }
    elsif ( $app eq 'webmail' ) {
        return ULC . "/base/webmail/$theme/banners";
    }
    return '';
}

=head2 _get_analytics_name(APP, SEGMENT)

Determin the Google Analytics key for this banners tracking.

=head3 ARGUMENTS

=over

=item APP - string

One of whm, cpanel, webmail

=item SEGMENT - string

The unique key for this banner.

=back

=head3 RETURNS

string - The GA key for this banner.

=cut

sub _get_analytics_name ( $app, $segment ) {
    if ( $app eq 'whm' ) {
        return "WHM_" . $segment;
    }
    elsif ( $app eq 'cpanel' ) {
        return return "CPANEL_" . $segment;
    }
    elsif ( $app eq 'webmail' ) {
        return "WEBMAIL_" . $segment;
    }

    return $segment;
}

=head2 _search_for_banner(APP_KEY, APP, THEME)

Search for a <APP_KEY>.json. The presense of this file means that we can
potentially show a banner on this page depending on the other rules defined
in the .json file.

=head3 ARGUMENTS

=over

=item APP_KEY - string

Unique key from dynamicui.conf for the application we want to show the banner
on. If APP_KEY = 'all', the banner will  be shown on all compatible pages where
an alternative banner is not already shown.

=item APP - string

One of whm, cpanel, webmail

=item THEME - string

The cpanel or webmail theme. For whm it is ignored.

=back

=head3 RETURNS

string - the path to the banners folder.

=cut

sub _search_for_banner {
    my ( $app_key, $app, $theme ) = @_;
    my @paths = _calculate_banner_paths( $app, $theme );

    foreach my $path (@paths) {
        foreach my $segment_key ( $app_key, 'all' ) {
            next if !$segment_key;
            my $test_path = "$path/$segment_key.json";
            return {
                segment => $segment_key,
                path    => $test_path,
            } if -e $test_path;
        }
    }

    return;
}

=head2 _matches_license_condition(EXCLUDE_WHEN)

See if we should exclude the banner for the given license condition.

=head3 ARGUMENTS

=over

=item EXCLUDE_WHEN - HASHREF

Where the keys are the license flag name and the values indicate if we should exclude the banner when the
flag is set (1) or not set (0). Leave keys off if you don't care to check that flag.

=over

=item trial - boolean

1 for trial flag on, 0 for trial flag off.

=item dev - boolean

1 for dev flag on, 0 for dev flag off.

=back

=back

=head3 RETURNS

boolean - 1 when we should not show the banner because the current license flags matched the rule, 0 otherwise.

=cut

sub _matches_license_condition($exclude_when) {
    foreach my $key ( keys %$exclude_when ) {
        next if !defined $exclude_when->{$key};
        my $has_flag = _has_license_flag($key);
        my $exclude  = $exclude_when->{$key} ? $has_flag : !$has_flag;
        return 1 if $exclude;
    }
    return 0;
}

=head2 _conditional_check_root(APP, CONFIG)

If the banner config requires root or the banner config is for whm and does not specify requires_root
check if the user is 'root'.

=cut

sub _conditional_check_root ( $app, $banner_json ) {

    # Check for root requirements if needed.
    my $requires_root = $banner_json->{requires_root};
    if ( !defined $requires_root && $app eq 'whm' ) {

        # default for whm to requiring root like the orignial system did.
        $requires_root = 1;
    }

    if ($requires_root) {
        require Whostmgr::ACLS;
        return 1 if Whostmgr::ACLS::hasroot();
        return 0;
    }
    return 1;
}

=head1 PUBLIC METHODS

=head2 get_banner_details(APP_KEY, APP, THEME)

Search for a <APP_KEY>.json. The presense of this file means that we can
potentially show a banner on this page depending on the other rules defined
in the .json file.

=head3 ARGUMENTS

=over

=item APP_KEY - string

Unique key from dynamicui.conf for the application we want to show the banner
on. If APP_KEY = 'all', the banner will  be shown on all compatible pages where
an alternative banner is not already shown.

=item APP - string

One of whm, cpanel, webmail

=item THEME - string

The cpanel or webmail theme. For whm it is ignored.

=back

=head3 RETURNS

HASHREF|UNDEF - the banner configuration if one if found.

=cut

sub get_banner_details {
    my ( $self, $app_key, $app, $theme ) = @_;

    my $banner_source = _search_for_banner( $app_key, $app, $theme );
    return if !$banner_source;

    require Cpanel::JSON;
    local $@;
    my $banner_json = eval { Cpanel::JSON::LoadFile( $banner_source->{path} ) };
    if ( !$banner_json ) {
        require Cpanel::Debug;
        require Cpanel::Exception;
        Cpanel::Debug::log_warn( "Failed to load banner $banner_source->{path}: " . Cpanel::Exception::get_string($@) );
        return;
    }

    return unless _conditional_check_root( $app, $banner_json );

    # Check if the banner can show based on the license type. Only supports trial and dev right now.
    # To only show in trail licensed products:
    #
    # {
    #     trial => 1
    # }
    #
    # To only show in non-trail, non-dev licensed products:
    #
    # {
    #     dev   => 0,
    #     trial => 0,
    # }
    #
    # To show in all produce licese types:
    #
    # {}
    my $exclude_when = $banner_json->{exclude_when};
    if ( !defined $exclude_when ) {
        $exclude_when = {};
        if ( $app eq 'whm' ) {

            # default for whm to excluding trial.
            $exclude_when->{trial} = 1;
        }
    }
    return if _matches_license_condition($exclude_when);

    # Check for required keys
    return if grep { !defined( $banner_json->{$_} ) } ('key');

    # TODO: Should have additional optional requirements checks
    #   companyid - one of list | pattern
    #   productid - one of list | pattern
    #   experimental flag

    # Defaults
    $banner_json->{include_default_css}    //= 1;
    $banner_json->{include_default_script} //= 1;

    my $module = $banner_json->{module};
    my $extension_obj;
    if ($module) {

        # Allow these to be shipped via plugins
        Cpanel::LoadModule::Custom::load_perl_module($module);
        $extension_obj = $module->new( redirect_path => $self->{'_CONTEXT'}->stash()->{'breadcrumburl'} );
    }

    if ( $extension_obj && $extension_obj->can('should_offer') ) {
        return if !$extension_obj->should_offer();
    }

    if ( $extension_obj && !$banner_json->{purchaselink} ) {
        if ( $extension_obj->can('purchaselink') ) {

            # legacy way of building the link
            $banner_json->{purchaselink} = $extension_obj->purchaselink( $banner_json->{purchaselink_suffix} );
        }
        elsif ( $extension_obj->can('purchase_link') ) {

            # modern way give the custom module access to the whole configuration
            $banner_json->{purchaselink} = $extension_obj->purchase_link($banner_json);
        }
    }

    if ($extension_obj) {
        if ( $extension_obj->can('get_product_price_text') ) {
            $banner_json->{purchasetext} = $extension_obj->get_product_price_text($banner_json);
        }
        elsif ( $banner_json->{purchasetext} && $extension_obj->can('get_product_price') ) {
            my $price = $extension_obj->get_product_price($banner_json);
            $banner_json->{purchasetext} =~ s/%PRICE%/\$$price/;
        }
    }

    if ( !$banner_json->{ignore_installed} ) {
        if ( $extension_obj && $extension_obj->can('is_installed') ) {
            return if $extension_obj->is_installed($banner_json);
        }
        else {
            require Cpanel::Market::ProductRequirements;
            return if Cpanel::Market::ProductRequirements::is_installed($banner_json);
        }
    }

    # Load it in a way we can easily mock and test, don't change to require
    Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
    my $locale = Cpanel::Locale->get_handle();

    if ( !defined $banner_json->{show_insufficiencies_when_detected} ) {
        if ( $app eq 'whm' ) {

            # preserved for existing banner behavior.
            $banner_json->{show_insufficiencies_when_detected} = 1;
        }
        else {
            $banner_json->{show_insufficiencies_when_detected} = 0;
        }
    }
    $banner_json->{insufficiencies} = [];

    if ( $extension_obj && $extension_obj->can('not_supported') ) {
        $banner_json->{sysreq_not_met} = $extension_obj->not_supported( $banner_json, $banner_source->{segment}, $locale );
    }
    elsif ( $app eq 'whm' ) {
        require Cpanel::Market::ProductRequirements;
        $banner_json->{sysreq_not_met} = Cpanel::Market::ProductRequirements::not_supported( $banner_json, $banner_source->{segment}, $locale );
    }
    else {
        $banner_json->{sysreq_not_met} = {};
    }

    if ( ref $banner_json->{sysreq_not_met} eq 'HASH' ) {
        foreach my $key ( keys( %{ $banner_json->{sysreq_not_met} } ) ) {

            # Don't show the banner
            return if $key eq 'disabled';
            push( @{ $banner_json->{insufficiencies} }, $banner_json->{sysreq_not_met}{$key} );
        }
    }

    # Put in appropriate tracking tags for analytics
    my $has_qs = index( $banner_json->{purchaselink}, '?' ) >= 0;
    require Whostmgr::GoogleAnalytics;
    $banner_json->{purchaselink} .= Whostmgr::GoogleAnalytics::utm_tags( $ENV{HOST}, "standard_banner", _get_analytics_name( $app, $banner_source->{segment} ), $has_qs );

    return $banner_json;
}

1;
