package Cpanel::Config::ConfigObj::Driver::Sitejet;

# cpanel - Cpanel/Config/ConfigObj/Driver/Sitejet.pm
#                                      Copyright 2024 WebPros International, LLC
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Config::ConfigObj::Driver::Sitejet

=head1 DESCRIPTION

Feature Showcase driver for Sitejet

=cut

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

use Cpanel::Config::ConfigObj::Driver::Sitejet::META ();
use Cpanel::Imports;

*VERSION = \$Cpanel::Config::ConfigObj::Driver::Sitejet::META::VERSION;

=head1 METHODS

=head2 init

Initializes the feature showcase object.

=cut

sub init ( $class, $software_obj ) {

    my $defaults = {
        'settings'      => {},
        'thirdparty_ns' => "",
    };

    my $self = $class->SUPER::base( $defaults, $software_obj );

    return $self;
}

=head2 set_default

We want this checked by default.

=cut

sub set_default { return 1; }

=head2 handle_showcase_submission

Process the input from the Feature Showcase.

=cut

sub handle_showcase_submission ( $self, $formref ) {
    my $selected_option = $formref->{'sitejet_enable_disable'};

    if ( $selected_option eq "EnableAll" ) {
        return $self->_update_setting(1);
    }
    elsif ( $selected_option eq "EnableDefault" ) {

        # TODO: move this block to a perl module and call it here and in modify_default_entrylist.pl
        # DUCK-10381
        require Cpanel::Features::Load;
        require Cpanel::Features::Write;
        my $feature_list = "default";
        my $key          = "sitejet";
        my $value        = 1;

        my $features = eval { Cpanel::Features::Load::load_featurelist($feature_list) };
        if ( $@ ) {
            logger()->warn("Unable to add default feature entry $key=$value: $@");
        }
        $features->{$key} = $value;
        Cpanel::Features::Write::write_featurelist( $feature_list, $features );
    }

    # Any other response, and it will keep the current settings

    return;
}

=head2 handle_showcase_submission

Updates the Sitejet feature in Feature Manager.

=cut

sub _update_setting ( $self, $new_setting ) {

    # TODO: move featurelist code into a module so we don't have to import this script
    # DUCK-10381

    require "/usr/local/cpanel/scripts/modify_default_featurelist_entry.pl";

    scripts::modify_default_featurelist_entry::modify_feature_for_all_feature_lists( "sitejet", $new_setting );

    return 1;
}

1;
