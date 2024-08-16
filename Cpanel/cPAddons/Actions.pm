package Cpanel::cPAddons::Actions;

# cpanel - Cpanel/cPAddons/Actions.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::cPAddons::Actions ();
use Cpanel::cPAddons::Globals ();
use Cpanel::cPAddons::Module  ();
use Cpanel::cPAddons::Util    ();
use Cpanel::Encoder::Tiny     ();
use Cpanel::Locale            ();

# Specials
use Cpanel::Imports;
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';

=head1 NAME

Cpanel::cPAddons::Actions

=head1 DESCRIPTION

cPanel-side handler functions for cPAddons actions (install, uninstall, upgrade, etc.)

=head1 ACTION

Most of the functions in this module take an action name. This is a string like 'install',
'uninstall', 'upgrade', etc.

=head1 MODULE DATA

Some of the functions in this module take a data structure called Module Data. Module Data
is a hash ref containing a collection of information about a cPAddons module.

Module Data is obtained via the Cpanel::cPAddons::Module::get_module_data() function based
on a known module name, so there should normally be no need to construct it manually.

See B<perldoc Cpanel::cPAddons::Module> for more information.

=head1 FUNCTIONS

=head2 init_module(ACTION, MODULE_DATA)

Initial setup that must be performed regardless of which action is being called.

=head3 Arguments

Accepts ACTION (see ACTION section above) and MODULE_DATA (see MODULE DATA section above).

=head3 Returns

Hash ref containing:

- error - String - (Only on failure) The reason the module couldn't be loaded.

- actions - Hash ref - Mapping of action names to the functions that perform the actual operations.

=cut

sub init_module {
    my ( $action, $module_data ) = @_;

    local @INC = ( '/usr/local/cpanel/cpaddons', @INC );

    Cpanel::cPAddons::Globals::init_globals();
    require Cpanel::cPAddons::Disabled;

    my $mod      = $module_data->{name};
    my $disabled = Cpanel::cPAddons::Disabled::check_if_action_is_disabled( $action, $mod );
    return { error => $disabled } if $disabled;

    my %response;
    return \%response if !Cpanel::cPAddons::Module::load_module( $mod, \%response );

    $response{actions} = setup_actions($module_data);

    return \%response;
}

=head2 setup_actions(MODULE_DATA)

Builds a collection of action functions from the cPAddons module for the addon being requested
(under /usr/local/cpanel/cpaddons/).

=head3 Arguments

Accepts MODULE_DATA (see MODULE DATA section above)

=head3 Returns

Hash ref of action names mapped to action functions from the module.

=cut

sub setup_actions {
    my ($module_data) = @_;

    my %actions;

    my $mod = $module_data->{name};
    for (qw(install upgrade manage uninstall installform manageform upgradeform uninstallform)) {
        my $nm = "$mod\:\:$_";
        eval { $actions{$_} = \&$nm; };
    }

    my $info = $module_data->{meta};

    $actions{'movecopy'}   = \&movecopy unless $info->{'nomovecopy'};
    $actions{'sendmodreq'} = sub { };

    if ( defined $info->{'specialfunctions'}
        && ref $info->{'specialfunctions'} eq 'HASH' ) {
        for ( keys %{ $info->{'specialfunctions'} } ) {
            if ( ref $info->{'specialfunctions'}->{$_}->{'code'} eq 'CODE'
                && !exists $actions{$_} ) {
                $actions{$_} = $info->{'specialfunctions'}->{$_}->{'code'};
            }
        }
    }

    return \%actions;
}

=head2 handle_install(MODULE_DATA, INPUT, SAFE_INPUT, ENV)

Handler function for cPAddon installs from the web UI or API.

=head3 Arguments

- MODULE_DATA - Hash ref - See MODULE DATA section above.

- INPUT - Hash ref - The form parameters from the client.

- SAFE_INPUT - Hash ref - HTML encoded version of the form parameters from the client.

- ENV - Hash ref - See perldoc B<Cpanel::cPAddons> for more info on ENV_HR.

=head3 Returns

- Cpanel::cPAddons::Obj

=cut

sub handle_install {
    my ( $module_data, $input, $safe_input, $env ) = @_;

    my $action   = $input->{'action'};
    my $response = init_module( $action, $module_data );
    my $actions  = setup_actions($module_data);

    require Cpanel::cPAddons::Defaults;
    Cpanel::cPAddons::Defaults::apply_defaults( $module_data, $input, $safe_input, $env )
      if $input->{'oneclick'} and $input->{'oneclick'} eq '1';

    require Cpanel::cPAddons::Obj;

    my $obj = Cpanel::cPAddons::Obj::create_obj(
        module_hr     => $module_data,
        env_hr        => $env,
        input_hr      => $input,
        safe_input_hr => $safe_input,
        response      => $response,
        mod           => $module_data->{name},
    );

    if ( $module_data->{is_deprecated} ) {
        $obj->add_error( locale()->maketext('This [asis,cPAddon] is deprecated. You cannot create new installations with this [asis,cPAddon].') );
    }
    elsif ( ref $response->{'actions'}{$action} eq 'CODE' ) {
        if ( !has_prerequisites( $action, $module_data, $input, $obj, $env ) ) {
            return $obj;
        }
        elsif ( !is_form_valid( $action, $module_data->{meta}, $input, $obj ) ) {
            return $obj;
        }
        else {
            $response->{'actions'}{$action}->( $obj, $module_data->{meta}, $input, $safe_input, $module_data, $env );
        }
    }
    else {
        $obj->add_info( locale()->maketext('This [asis,cPAddon] does not support installation.') );
    }

    return $obj;
}

=head2 handle_upgrade(MODULE_DATA, INPUT, SAFE_INPUT, ENV)

Handler function for cPAddon upgrades from the web UI or API.

=head3 Arguments

- MODULE_DATA - Hash ref - See MODULE DATA section above.

- INPUT - Hash ref - The form parameters from the client.

- SAFE_INPUT - Hash ref - HTML encoded version of the form parameters from the client.

- ENV - Hash ref - See perldoc B<Cpanel::cPAddons> for more info on ENV (aka $env_hr).

=head3 Returns

- Cpanel::cPAddons::Obj

=cut

sub handle_upgrade {
    my ( $module_data, $input, $safe_input, $env ) = @_;

    my $action   = $input->{'action'};
    my $response = init_module( $action, $module_data );
    my $actions  = setup_actions($module_data);

    require Cpanel::cPAddons::Obj;

    my $obj = Cpanel::cPAddons::Obj::create_obj(
        module_hr     => $module_data,
        env_hr        => $env,
        input_hr      => $input,
        safe_input_hr => $safe_input,
        response      => $response,
        mod           => $module_data->{name},
    );

    if ( ref $response->{'actions'}{$action} eq 'CODE' ) {

        if ( !has_prerequisites( $action, $module_data, $input, $obj, $env ) ) {
            return $obj;
        }
        elsif ( !is_form_valid( $action, $module_data->{meta}, $input, $obj ) ) {
            return $obj;
        }
        else {
            $response->{'actions'}{$action}->( $obj, $module_data->{meta}, $input, $safe_input, $module_data, $env );
        }
    }
    else {
        $obj->add_info( locale()->maketext('This [asis,cPAddon] does not support upgrades.') );
    }
    return $obj;
}

=head2 handle_uninstall(MODULE_DATA, INPUT, SAFE_INPUT, ENV)

Handler function for cPAddon uninstalls from the web UI or API.

=head3 Arguments

- MODULE_DATA - Hash ref - See MODULE DATA section above.

- INPUT - Hash ref - The form parameters from the client.

- SAFE_INPUT - Hash ref - HTML encoded version of the form parameters from the client.

- ENV - Hash ref - See perldoc B<Cpanel::cPAddons> for more info on ENV.

=head3 Returns

- Cpanel::cPAddons::Obj

=cut

sub handle_uninstall {
    my ( $module_data, $input, $safe_input, $env ) = @_;

    my $action   = $input->{'action'};
    my $response = init_module( $action, $module_data );
    my $actions  = setup_actions($module_data);

    require Cpanel::cPAddons::Obj;

    my $obj = Cpanel::cPAddons::Obj::create_obj(
        module_hr     => $module_data,
        env_hr        => $env,
        input_hr      => $input,
        safe_input_hr => $safe_input,
        response      => $response,
        mod           => $module_data->{name},
    );

    if ( ref $response->{'actions'}{$action} eq 'CODE' ) {

        if ( !has_prerequisites( $action, $module_data, $input, $obj, $env ) ) {
            return $obj;
        }
        elsif ( !is_form_valid( $action, $module_data->{meta}, $input, $obj ) ) {
            return $obj;
        }
        else {
            $response->{'actions'}{$action}->( $obj, $module_data->{meta}, $input, $safe_input, $module_data, $env );
        }
    }
    else {
        $obj->add_info( locale()->maketext('This [asis,cPAddon] does not support uninstall.') );
    }
    return $obj;
}

=head2 handle_other(MODULE_DATA, INPUT, SAFE_INPUT, ENV)

Handler function for any other cPAddons operations from the web UI or API.

=head3 Arguments

- MODULE_DATA - Hash ref - See MODULE DATA section above.

- INPUT - Hash ref - The form parameters from the client.

- SAFE_INPUT - Hash ref - HTML encoded version of the form parameters from the client.

- ENV - Hash ref - See perldoc B<Cpanel::cPAddons> for more info on ENV_HR.

=head3 Returns

- Cpanel::cPAddons::Obj

=cut

sub handle_other {
    my ( $module_data, $input, $safe_input, $env ) = @_;

    my $action   = $input->{'action'};
    my $response = init_module( $action, $module_data );
    my $actions  = setup_actions($module_data);

    require Cpanel::cPAddons::Obj;

    my $obj = Cpanel::cPAddons::Obj::create_obj(
        module_hr     => $module_data,
        env_hr        => $env,
        input_hr      => $input,
        safe_input_hr => $safe_input,
        response      => $response,
        mod           => $module_data->{name},
    );

    if ( ref $response->{'actions'}{$action} eq 'CODE' ) {

        if ( !has_prerequisites( $action, $module_data, $input, $obj, $env ) ) {
            return $obj;
        }
        elsif ( !is_form_valid( $action, $module_data->{meta}, $input, $obj ) ) {
            return $obj;
        }
        else {
            $response->{'actions'}{$action}->( $obj, $module_data->{meta}, $input, $safe_input, $module_data, $env );
        }
    }
    else {
        $obj->add_info( locale()->maketext( 'The [asis,cPAaddon] does not support the action: [_1].', Cpanel::Encoder::Tiny::safe_html_encode_str($action) ) );
    }
    return $obj;
}

sub handle_moderation {
    my ( $module_data, $input, $safe_input, $env ) = @_;
    $env = {} if !$env;

    my $action   = $input->{'action'};
    my $response = init_module( $action, $module_data );
    my $actions  = setup_actions($module_data);

    require Cpanel::cPAddons::Obj;

    my $obj = Cpanel::cPAddons::Obj::create_obj(
        module_hr     => $module_data,
        env_hr        => $env,
        input_hr      => $input,
        safe_input_hr => $safe_input,
        response      => $response,
        mod           => $module_data->{name},
    );

    my $valid = is_form_valid( $action, $module_data->{meta}, $input, $obj );    # Side effect: Adds error info, if applicable, to $obj

    return $obj;
}

my $settings = {
    no_modified_cpanel => Cpanel::cPAddons::Util::get_no_modified_cpanel_addons_setting() ? 1 : 0,
    no_3rd_party       => Cpanel::cPAddons::Util::get_no_3rd_party_addons_setting()       ? 1 : 0,
};

sub has_prerequisites {
    my ( $action, $module, $input, $obj, $env ) = @_;

    # Check for prerequisites.
    if ( $settings->{no_modified_cpanel} && $module->{is_modified} ) {
        $obj->add_critical_error( locale()->maketext( 'This server disallows modified [_1] [asis,addons]. Contact your hosting provider for more information.', Cpanel::Encoder::Tiny::safe_html_encode_str( $module->{vendor} ) ) )
          if !$obj->{checked}{no_modified_cpanel};
        $obj->{checked}{no_modified_cpanel} = 1;
        return 0;
    }

    if ( $settings->{no_3rd_party} && $module->{is_3rd_party} ) {
        $obj->add_critical_error( locale()->maketext('This server disallows 3rd party [asis,addons]. Contact your hosting provider for more information.') )
          if !$obj->{checked}{no_3rd_party};
        $obj->{checked}{no_3rd_party} = 1;
        return 0;
    }

    return 1 if !( grep { $action eq $_ } qw(install upgrade uninstall) );

    if ( grep { $action eq $_ } qw(install upgrade) ) {

        if ( $module->{meta}{require_suexec} && !suexec() ) {
            $obj->add_critical_error( locale()->maketext('This [asis,cPAddon] requires [asis,suEXEC] for file permission security. Ask your hosting provider to enable [asis,suEXEC].') )
              if !$obj->{checked}{require_suexec};
            $obj->{checked}{require_suexec} = 1;
            return 0;
        }

        if ( exists $module->{meta}{'minimum-mysql-version'} && $module->{meta}{'minimum-mysql-version'} =~ m/\A[0-9](?:\.[0-9]+)?\z/ ) {
            if ( $env->{mysql_version} < $module->{meta}{'minimum-mysql-version'} ) {
                $obj->add_critical_error(
                    locale()->maketext(
                        "[asis,MySQL] version [_1] or later must run on the server. The installed version is [_2].",
                        Cpanel::Encoder::Tiny::safe_html_encode_str( $module->{meta}{'minimum-mysql-version'} ),
                        Cpanel::Encoder::Tiny::safe_html_encode_str( $env->{mysql_version} )
                    )
                ) if !$obj->{checked}{'minimum-mysql-version'};
                $obj->{checked}{'minimum-mysql-version'} = 1;
                return 0;
            }
        }

        if ( $module->{meta}{vendor_license} ) {
            if ( !defined $obj->{license_valid} ) {
                require Cpanel::cPAddons::License;

                # Only run this once per cycle
                Cpanel::cPAddons::License::check_license( $obj, $module->{meta}, $input );
                if ( !$obj->{license_valid} ) {
                    if ( $obj->{license_error} ) {
                        $obj->add_critical_error(
                            locale()->maketext('The vendor reported that the license you entered is invalid. Contact the vendor for additional assistance.'),
                            {
                                id         => 'license-invalid-error',
                                list_items => [
                                    locale->maketext( 'Error: [_1]', Cpanel::Encoder::Tiny::safe_html_encode_str( $obj->{license_error} ) ),
                                ],
                            }
                        ) if !$obj->{checked}{vendor_license};
                    }
                    else {
                        $obj->add_critical_error( locale()->maketext('The vendor reported that the license you entered is invalid. Contact the vendor for additional assistance.') )
                          if !$obj->{checked}{vendor_license};
                    }
                }
                $obj->{checked}{vendor_license} = 1;
                return 0;
            }
            elsif ( !$obj->{license_valid} ) {
                return 0;
            }
        }
    }

    return 1;
}

sub is_form_valid {
    my ( $action, $info, $input, $obj ) = @_;

    return 1 if !( grep { $action eq $_ } qw(install moderate) );

    if ( $info->{adminuser_pass} ) {
        my $len =
            $info->{'admin_user_pass_length'} =~ m/^\d+$/
          ? $info->{'admin_user_pass_length'}
          : $obj->{'default_minimum_pass_length'};

        if ( length $obj->{'username'} < $len ) {
            $obj->add_error( locale()->maketext( 'Your username requires at least [_1] letters and numbers.', $len ) );
        }

        if ( length $obj->{'password'} < $len ) {
            $obj->add_error( locale()->maketext( 'Your password requires at least [_1] letters and numbers.', $len ) );
        }

        if ( $obj->{'password'} ne $obj->{'password2'} ) {
            $obj->add_error( locale()->maketext('Both admin password entries must match.') );
        }

        if ( $obj->{'password'} =~ m/["']/ ) {
            $obj->add_error( locale()->maketext('The [asis,cPAddon] does not support passwords with double quote or single quote.') );
        }

        my $app = 'cpaddons';
        require Cpanel::PasswdStrength::Check;
        if ( $len && !Cpanel::PasswdStrength::Check::check_password_strength( 'pw' => $obj->{'password'}, 'app' => $app ) ) {

            my $required_strength = Cpanel::PasswdStrength::Check::get_required_strength($app);
            $obj->add_error(
                locale()->maketext(
                    'Your password does not meet the system’s strength requirements. Enter a password with strength rating of [_1] or higher.',
                    $required_strength,
                )
            );
        }

        my $max =
            $info->{'admin_user_pass_length_max'} =~ m/^\d+$/
          ? $info->{'admin_user_pass_length_max'}
          : 0;

        if ($max) {
            if ( length $obj->{'username'} > $max ) {
                $obj->add_error(
                    locale()->maketext(
                        'Your username cannot exceed [_1] letters and numbers.',
                        $max
                    )
                );
            }

            if ( length $obj->{'password'} > $max ) {
                $obj->add_error( locale()->maketext( 'Your password cannot exceed [_1] letters and numbers.', $max ) );
            }
        }
    }

    if ( $info->{admin_email} ) {
        require Cpanel::CheckData;
        if ( !Cpanel::CheckData::isvalidemail( $obj->{'email'} ) ) {
            $obj->add_error( locale()->maketext('You must specify a valid email address.') );
        }
    }

    if ( ref $info->{install_fields_hook} eq 'CODE'
        && $input->{action} eq 'install' ) {

        my $user_err = '';
        $info->{install_fields_hook}->( $input, \$user_err, $obj );
        if ($user_err) {
            $obj->add_error($user_err);
        }
    }

    my $has_issues = $obj->{notices}->has( 'critical_error', 'error' );
    return !$has_issues;
}

# TODO: Move to Runtime
sub suexec {
    return -x apache_paths_facade->bin_suexec() ? 1 : 0;
}

1;
