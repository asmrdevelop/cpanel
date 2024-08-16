
# cpanel - Cpanel/iContact/Providers.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::iContact::Providers;

use strict;
use Cpanel::ConfigFiles        ();
use Cpanel::ArrayFunc::Uniq    ();
use Cpanel::LoadModule::Name   ();
use Cpanel::LoadModule::Custom ();

my @module_list;
my %KNOWN_PROVIDERS = ();

my $namespace  = 'Cpanel::iContact::Provider::Schema';
my $schema_dir = 'Cpanel/iContact/Provider/Schema';
our $MODULE_DIR         = "$Cpanel::ConfigFiles::CPANEL_ROOT/$schema_dir";
our $CUSTOM_MODULES_DIR = "$Cpanel::ConfigFiles::CUSTOM_PERL_MODULES_DIR/$schema_dir";

my @displays_keys = qw(display_name icon_name icon verification_api);

=encoding utf-8

=head1 NAME

Cpanel::iContact::Providers - Internal hooks for loading iContact providers

=head1 DESCRIPTION

These functions are accessed by internal hook points and are not
intended to be called anywhere else.

=head2 get_settings

Return settings to augment the %Conf hash in Whostmgr::TweakSettings::Basic
It is not intended to be called by any other function.

=head3 Input

None

=head3 Output

None

=cut

my %Conf;

sub get_settings {
    return %Conf if %Conf;
    foreach my $module ( _get_all_icontact_modules() ) {
        %Conf = ( %Conf, %{ "$namespace\:\:$module"->get_settings() } );
    }

    return %Conf;
}

=head2 augment_shadow_keys

Augment Cpanel::Config::SaveWwwAcctConf::savewwwacctconf's list of
keys that need to be shadowed.
It is not intended to be called by any other function.

=head3 Input

None

=head3 Output

None

=cut

sub augment_shadow_keys {
    my ($shadow_ref) = @_;

    foreach my $module ( _get_all_icontact_modules() ) {
        my $ref = "$namespace\:\:$module"->get_settings();
        foreach my $setting ( keys %{$ref} ) {
            if ( $ref->{$setting}{'shadow'} ) {
                $shadow_ref->{$setting} = '';
            }
        }

    }
    return 1;

}

=head2 augment_icontact_providers

Augment Cpanel::iContact::_send_notifications's %ICONTACT_PROVIDERS list
It is not intended to be called by any other function.

=head3 Input

None

=head3 Output

None

=cut

sub augment_icontact_providers {
    my ($providers_ref) = @_;

    foreach my $module ( _get_all_icontact_modules() ) {
        $providers_ref->{ _key_from_module($module) } = $module;
    }
    return 1;

}

=head2 augment_method_display

Augment whostmgr2.pl %CONTACTS list
It is not intended to be called by any other function.

=head3 Input

None

=head3 Output

None

=cut

sub augment_method_display {
    my ($method_display_ref) = @_;

    foreach my $module ( _get_all_icontact_modules() ) {
        my $modname = _key_from_module($module);
        my $ref     = "$namespace\:\:$module"->get_config();
        foreach my $display_key (@displays_keys) {
            if ( exists $ref->{$display_key} ) {
                $method_display_ref->{$modname}{$display_key} = $ref->{$display_key};
            }
        }
    }
    return 1;

}

=head2 augment_contacts_with_default_levels

Augment Cpanel::iContact::_loadcontactsettings's %CONTACTS list
It is not intended to be called by any other function.

=head3 Input

None

=head3 Output

None

=cut

sub augment_contacts_with_default_levels {
    my ($contact_ref) = @_;

    foreach my $module ( _get_all_icontact_modules() ) {
        $contact_ref->{ _key_from_module($module) }{'level'} = $Cpanel::iContact::RECEIVES_NAME_TO_NUMBER{ "$namespace\:\:$module"->get_config()->{'default_level'} } // $Cpanel::iContact::RECEIVES_NAME_TO_NUMBER{'All'};
    }
    return 1;
}

=head2 augment_tweak_texts

Augment Whostmgr::TweakSettings::get_texts for the Basic
tweak settings modules.

It is not intended to be called by any other function.

=head3 Input

None

=head3 Output

None

=cut

sub augment_tweak_texts {
    my ($tweak_text_ref) = @_;

    my %known_keys = map { $_ => 1 } @{ $tweak_text_ref->{'TS_display'}->[0]->[1] };

    foreach my $module ( _get_all_icontact_modules() ) {
        my $ref = "$namespace\:\:$module"->get_settings();

        foreach my $setting ( sort keys %{$ref} ) {
            if ( !exists $known_keys{$setting} ) {
                push @{ $tweak_text_ref->{'TS_display'}->[0]->[1] }, $setting;
                $known_keys{$setting} = 1;
            }
            $tweak_text_ref->{$setting} ||= $ref->{$setting};
        }

    }

    return 1;

}

=head2 augment_contact_settings

Augment the passed in %CONTACTS hash with 'custom' values from provider modules:
This way, if you have settings that aren't like 'CONTACTX', they will be added to your contact ref
in the context of Cpanel::iContact::Provider::MyCustomModuleNameHere

It is not intended to be called by any other function than Cpanel::iContact::_loadcontactsettings().

=head3 Input

A hash of contact information you'd normally get from within Cpanel::iContact::_loadcontactsettings().

=head3 Output

The augmented %CONTACTS hash.

=cut

sub augment_contact_settings {
    my ( $wwwacct_ref, $contacts ) = @_;
    foreach my $module ( _get_all_icontact_modules() ) {
        my $ref = "$namespace\:\:$module"->get_settings();
        foreach my $setting ( keys %{$ref} ) {

            # Load the setting from schema UNLESS it matches the CONTACTMYMODULENAME string, as that's the key we're inserting the setting *underneath*.
            my $key_from_module = _key_from_module($module);
            $contacts->{$key_from_module}{$setting} = $wwwacct_ref->{$setting} if $setting ne $key_from_module;
        }
    }
    return $contacts;
}

sub _get_all_icontact_modules {
    return @module_list if @module_list;

    require Cpanel::iContact;

    # Sorted so random order problems don't bite us
    @module_list = sort( Cpanel::ArrayFunc::Uniq::uniq(
            Cpanel::LoadModule::Name::get_module_names_from_directory($CUSTOM_MODULES_DIR),
            Cpanel::LoadModule::Name::get_module_names_from_directory($MODULE_DIR),
    ) );

    foreach my $module (@module_list) {
        Cpanel::LoadModule::Custom::load_perl_module("$namespace\:\:$module") if !$INC{"$schema_dir/$module.pm"};
    }

    return @module_list;
}

sub _key_from_module {
    return 'CONTACT' . uc( $_[0] );
}

1;
