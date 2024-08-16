package Cpanel::Template::Plugin::Master;

# cpanel - Cpanel/Template/Plugin/Master.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Template::Plugin';

use Cpanel::DynamicUI::App ();
use Cpanel::API::NVData    ();
use Cpanel::API::cPAddons  ();

=head1 NAME

Cpanel::Template::Plugin::Master

=head1 DESCRIPTION

Plugin that loads various master page related data into the varcache.

=head1 VARCACHE

=over

=item application_group_order

Order of application groups on the home page. Only meaningful for cPanel.

=item collapsed_groups

Which application groups are collapsed. Only meaningful for cPanel.

=item available_applications

List of available applications. Only meaningful for cPanel.

=item upgrade_app_info

Upgrade information use when the limits are near (80%) or at maximum
and beyond. Provides information to the render and may contain URLs
for external products that allow you to pay for more of the limited
resource.

=item available_addons

List of available addons. Used in the menu system.

=back

=head1 METHODS

=head2 C<load(CLASS, CONTEXT)>

Internal method that is called when the plugin loads.

=head3 Arguments

Arguments are positional.

=over

=item CLASS - string - Class name of this plugin

=item CONTEXT - object - Template toolkit context.

=back

=head3 Returns

See documentation in Template Toolkit Plugin API for expected return type.

=cut

sub load {
    my ( $class, $context ) = @_;

    my $varcache = $context->{CONFIG}{NAMESPACE}{varcache};

    # Stuff our data into the varcache
    if ($varcache) {

        my $application_group_order = Cpanel::API::NVData::_get('xmaingroupsorder')->[0]{value}      || 1;
        my $collapsed_groups        = Cpanel::API::NVData::_get('xmainrollstatus')->[0]{value}       || '';
        my $welcome_dismissed       = Cpanel::API::NVData::_get('xmainwelcomedismissed')->[0]{value} || 0;
        my $available_applications  = Cpanel::DynamicUI::App::get_available_applications( 'arglist' => $application_group_order, 'need_description' => 1 );
        my $upgrade_app_info        = Cpanel::DynamicUI::App::get_implementer_from_available_applications( $available_applications, 'upgrade' );
        my $available_addons        = Cpanel::API::cPAddons::_get_available_addons();

        #Collect the user's CREATED_IN_VERSION and extract the major version (so it can be treated as a numeric value)
        my $created_in_version       = $Cpanel::CPDATA{'CREATED_IN_VERSION'} || "";
        my @version                  = split /\./, $created_in_version;
        my $created_in_version_major = ( scalar @version > 1 ) ? $version[1] : "";

        $varcache->set( 'application_group_order',  $application_group_order );
        $varcache->set( 'collapsed_groups',         $collapsed_groups );
        $varcache->set( 'welcome_dismissed',        $welcome_dismissed );
        $varcache->set( 'available_applications',   $available_applications );
        $varcache->set( 'upgrade_app_info',         $upgrade_app_info );
        $varcache->set( 'available_addons',         $available_addons );
        $varcache->set( 'created_in_version_major', $created_in_version_major );
        $varcache->set( 'display_welcome_panel',    _can_display_welcome_panel($available_applications) );
    }

    return $class->SUPER::load($context);
}

sub _can_display_welcome_panel {
    my ($apps) = @_;                                                          #We need a list of available apps to judge against
    my $nav_data = Cpanel::API::NVData::_get('cp-welcome-panel_dismissed');
    if ( $nav_data && $nav_data->[0]{value} ) { return 0; }                   #If it's dismissed, that's all we need to know

    require Cpanel::WPTK::Site;                                               #Lazy load to avoid unnecessary overhead
    if ( Cpanel::WPTK::Site::is_docroot_empty() == 0 ) { return 0; }          #If their docroot is contaminated, do not show

    my $has_backup_feature  = ( exists $apps->{index}->{'backup'} )                ? 1 : 0;    #Do they have the Backup feature?
    my $has_wptk_feature    = ( exists $apps->{index}->{'wp-toolkit'} )            ? 1 : 0;    #Do they have the WPTK feature?
    my $has_sitejet_feature = ( exists $apps->{index}->{'cpanel-sitejet-plugin'} ) ? 1 : 0;    #Do they have the sitejet feature?
    return $has_backup_feature || $has_wptk_feature || $has_sitejet_feature;                   #They only need one of the three
}

1;
