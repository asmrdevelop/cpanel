package Whostmgr::TweakSettings;

# cpanel - Whostmgr/TweakSettings.pm               Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

## no critic qw(TestingAndDebugging::RequireUseWarnings) -- Whostmgr::TweakSettings is not yet warnings safe

use Cpanel::Debug                        ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::IxHash                       ();
use Cpanel::Locale                       ();
use Cpanel::Locale::Utils::Display       ();
use Cpanel::Logger                       ();
use Cpanel::LoadModule                   ();

my $logger;

=encoding utf-8

=head1 NAME

Whostmgr::TweakSettings - This module is used for validation and getting of the TweakSettings namespaces/settings.

=head1 SYNOPSIS

    use Whostmgr::TweakSettings ();

    my $apache_settings_defaults = Whostmgr::TweakSettings::get_conf("Apache");

=head1 DESCRIPTION

This module allows for the getting and/or validation of the configuration settings for the different TweakSettings namespaces/modules in the product.
The different namespaces can be found under /u/l/c/Whostmgr/TweakSettings/*

=cut

=head2 process_input_values

This function is used to validate new TweakSettings values and return conflicts or issues with the settings.

=head3 Input

=over 3

=item C<SCALAR> namespace

    The name of the TweakSettings namespace module to load and validate settings for.
    These modules can be found under /u/l/c/Whostmgr/TweakSettings/*

=item C<HASHREF> input_values_h

    This is a hashref of new TweakSettings for the specified namespace. These values will be validated
    and conflicts/issues returned. The hashref should be in the form of SETTING_NAME => VALUE. You can
    find out the correct values for a specific key by checking the TweakSettings namespace module for the
    namespace you're operating on.

=item C<HASHREF> - OPTIONAL - current_conf_values

    This optional value is used to protect against a race condition if the values on disk changed between someone
    loading the page and saving the page.

=back

=head3 Output

=over 3

=item C<HASHREF> newvalues

    A hashref of values that are the validated and acceptable settings to save for the specified TweakSettings namespace.
    This is in the same format as the input_values_h in input. This is the only value returned when the function is called in scalar context.

=item C<HAHSREF> - OPTIONAL - rejects

    A hashref of rejected TweakSettings for the specified namespace. This return is optional and will only be returned in list context.

=item C<HAHSREF> - OPTIONAL - reject_reasons

    A hashref of rejection reasons for TweakSettings for the specified namespace. This return is optional and will only be returned in list context.

=item C<HAHSREF> - OPTIONAL - conflicts

    A hashref of conflicted TweakSettings for the specified namespace. This return is optional and will only be returned in list context.

=back

=head3 Exceptions

None.

=cut

#take an input hash and compare it to the appropriate "Conf" variable,
#returning the formatted/sanitized values and the "rejects"
sub process_input_values {    ## no critic(Subroutines::RequireArgUnpacking Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    local $Cpanel::IxHash::Modify = 'none';

    my ( $namespace, $input_values_h, $current_conf_values ) = @_;

    # For most of this function we expect $input_values_h to include
    # anything from $current_conf_values; however, we also need not to
    # “reject” anything that wasn’t actually provided, so we keep track
    # here of the %just_plain_inputs.

    my %just_plain_inputs = %$input_values_h;

    # … and here we actually combine the old and new.
    if ($current_conf_values) {
        $input_values_h = {
            %$current_conf_values,
            %$input_values_h,
        };
    }

    my $conf_h = get_conf_cached($namespace);

    unless ( scalar %{$conf_h} ) {
        $logger ||= Cpanel::Logger->new();
        $logger->warn("Could not load tweaksettings for $namespace");
        return;
    }

    my ( %newvalues, %rejects, %reject_reasons );

    foreach my $key ( keys %{$conf_h} ) {
        my $cur_settings = $conf_h->{$key};

        next if defined $cur_settings->{'type'} && $cur_settings->{'type'} eq 'button';

        # Skip processing some settings. Note:  will also prevent settings from displaying on the form.
        next if ( exists $cur_settings->{'skipif'}
            && ref $cur_settings->{'skipif'} eq 'CODE'
            && $cur_settings->{'skipif'}->($input_values_h) );

        # Ignore some settings. Note that this only causes settings to be ignored on the backend.
        next if ( exists $cur_settings->{'ignoreif'}
            && ref $cur_settings->{'ignoreif'} eq 'CODE'
            && $cur_settings->{'ignoreif'}->($input_values_h) );

        my $required_setting = $cur_settings->{'requires'};

        # Verify that dependent settings are enabled
        if ( $required_setting && !_has_required_setting( { 'setting' => $key, 'required_setting' => $required_setting, 'current_config' => $current_conf_values, 'input' => $input_values_h } ) ) {

            # Only “reject” a setting that was submitted in the first place.
            if ( exists $just_plain_inputs{$key} ) {
                $rejects{$key}        = $key;
                $reject_reasons{$key} = "$key requires $required_setting";
            }

            next;
        }
        my $control_val = $input_values_h->{ $key . '_control' };
        if ( defined $control_val ) {

            #set to undef only if specifically told to do so
            if ( $control_val eq 'undef' && $cur_settings->{'can_undef'} ) {
                $newvalues{$key} = undef;
                next;
            }

            #use default value; if none is set, this disables the setting
            elsif ( $control_val eq 'default' ) {
                $newvalues{$key} = $cur_settings->{'default'};
                next;
            }

            #use PCI recommended value
            elsif ( $control_val eq 'pci' ) {
                $newvalues{$key} = $cur_settings->{'pci'};
                next;
            }

            #use a custom-listed value
            elsif ( $control_val =~ m{\Acustom_(.*)\z} ) {
                $newvalues{$key} = $1;
                next;
            }

            delete $input_values_h->{ $key . '_control' };
        }

        if ( defined $cur_settings->{'type'} && $cur_settings->{'type'} eq 'multiselect' ) {
            next if !defined $input_values_h->{$key};

            #Compensate for Cpanel::Form
            my $vals_ar = $input_values_h->{$key};

            $vals_ar = [] if !$vals_ar;

            # Compensate for value being stored as a hashref on disk
            if ( ref $vals_ar eq 'HASH' ) {
                $vals_ar = [ map { $vals_ar->{$_} ? $_ : () } keys %$vals_ar ];
            }

            if ( !ref $vals_ar ) {
                my @keys = sort { ( $a =~ m{-(\d+)\z} ? int $1 : -1 ) <=> ( $b =~ m{-(\d+)\z} ? int $1 : -1 ) } ( grep { m{\A\Q$key\E} } keys(%$input_values_h) );
                if ( scalar @keys == 1 && $vals_ar =~ tr/,// ) {

                    # xml-api case.
                    $vals_ar = [ split /,/, $vals_ar ];
                }
                else {
                    # Tweak Settings case.
                    $vals_ar = [ map { $input_values_h->{$_} } @keys ];
                }
            }

            my $checkval_ref = exists $cur_settings->{'checkval'} && ref $cur_settings->{'checkval'};
            if ( $checkval_ref && $checkval_ref eq 'CODE' ) {

                my ( $checked_val, $reason ) = $cur_settings->{'checkval'}->($vals_ar);

                if ( defined $checked_val ) {    #defined means valid
                    $vals_ar = $checked_val;
                }
                else {                           #we get here if we failed validation
                    $rejects{$key}        = join( ' ', @$vals_ar );
                    $reject_reasons{$key} = ( $reason || 'Value does not meet data requirements' );
                    next;
                }
            }

            my %off = map { $_ => 0 } @{ $cur_settings->{'options'} };

            my ( %on, @rejects );
            for my $cur_val (@$vals_ar) {
                if ( exists $off{$cur_val} ) {
                    $on{$cur_val} = 1;
                }
                else {
                    push @rejects, $cur_val;
                }
            }

            if ( scalar @rejects ) {
                $rejects{$key}        = \@rejects;
                $reject_reasons{$key} = "Value is not a valid key";
            }
            else {
                $newvalues{$key} = { %off, %on };
            }

            next;
        }

        if ( defined $cur_settings->{'type'} && $cur_settings->{'type'} eq 'locale' ) {
            next if !exists $input_values_h->{$key};

            my $locale = Cpanel::Locale->get_handle();
            my $val    = $input_values_h->{$key};
            if ( grep { $_ eq $val } Cpanel::Locale::Utils::Display::get_locale_list($locale) ) {
                $newvalues{$key} = $val;
            }
            else {
                $rejects{$key}        = $val;
                $reject_reasons{$key} = "Value is not a valid Locale";
            }

            next;
        }

        my $cur_inputval =
          exists $input_values_h->{ $key . '_other' }
          ? $input_values_h->{ $key . '_other' }
          : $input_values_h->{$key};

        if ( defined $cur_inputval ) {
            my $checkval_ref = exists $cur_settings->{'checkval'}
              && ref $cur_settings->{'checkval'};
            my $settings_type = $cur_settings->{'type'};

            #scrub/sanitize/validate
            if ( $checkval_ref && $checkval_ref eq 'CODE' ) {
                my ( $checked_val, $reason ) = $cur_settings->{'checkval'}->($cur_inputval);

                if ( defined $checked_val ) {    #defined means valid
                    $newvalues{$key} = $checked_val;
                }
                else {                           #we get here if we failed validation
                    $rejects{$key}        = $cur_inputval;
                    $reject_reasons{$key} = ( $reason || 'Value does not meet data requirements' );
                }
            }
            elsif ( exists $cur_settings->{'options'}
                || ( $settings_type && ( $settings_type eq 'binary' || $settings_type eq 'inversebinary' ) ) ) {
                my $checked_val = validate_setting( $cur_settings, $cur_inputval );

                if ( defined $checked_val ) {    #defined means valid
                    $newvalues{$key} = $checked_val;
                }
                else {                           #we get here if we failed validation

                    $rejects{$key} = $cur_inputval;

                    if ( $settings_type && $settings_type eq 'binary' ) {
                        $reject_reasons{$key} = "Value must be either 0 or 1";
                    }
                    else {

                        my @valid_options;

                        if ( ref $cur_settings->{'options'}->[0] eq 'ARRAY' ) {
                            @valid_options = map { $_->[1] } @{ $cur_settings->{'options'} };
                        }
                        else {
                            @valid_options = @{ $cur_settings->{'options'} };
                        }

                        $reject_reasons{$key} = Cpanel::Locale->get_handle()->maketext( "The parameter “[_1]” must be [list_or_quoted,_2].", $key, \@valid_options );
                    }

                }
            }
            else {
                $newvalues{$key} = $cur_inputval;
            }

        }

        if ( !defined $newvalues{$key} && $cur_settings->{'can_undef'} ) {
            next;    # no need to do min max checks if undef is allowed
        }

        if (
            defined $cur_settings->{'minimum'} && exists $newvalues{$key}                                 # .
            && ( ( $newvalues{$key} // 0 ) ne 'disabled' && $cur_settings->{'minimum'} ne 'disabled' )    # .
            && ( $newvalues{$key} // 0 ) < $cur_settings->{'minimum'}
          ) {                                                                                             # .
            $rejects{$key}        = delete $newvalues{$key};
            $reject_reasons{$key} = "Value is below minimum";
        }
        if (
               defined $cur_settings->{'maximum'}
            && exists $newvalues{$key}
            && ( ( $newvalues{$key} // 0 ) ne 'disabled' && $cur_settings->{'maximum'} ne 'disabled' )    # .
            && ( $newvalues{$key} // 0 ) > $cur_settings->{'maximum'}                                     # .
        ) {
            $rejects{$key}        = delete $newvalues{$key};
            $reject_reasons{$key} = "Value exceeds maximum";
        }

        #Verify the home directory is present
        if ( ( $key eq "HOMEDIR" ) && ( defined $newvalues{$key} ) && ( !-d $newvalues{$key} ) ) {    #if we've got a homedir and it doesn't exist...
            $rejects{$key}        = delete $newvalues{$key};                                          #reject this setting outright...
            $reject_reasons{$key} = "This home directory does not exist.";                            #and tell the user why.
        }
    }

    for ( keys %newvalues ) {
        if ( 'CODE' eq ref $newvalues{$_} ) {
            $newvalues{$_} = $newvalues{$_}->( \%newvalues );
        }
    }

    my %conflicts;
    if ($current_conf_values) {
        %conflicts = _check_for_update_conflicts(
            'current_conf_values' => $current_conf_values,
            'new_values'          => \%newvalues,
            'input_values'        => $input_values_h,
            'namespace'           => $namespace,
        );
    }

    my $post_process_cr = eval { ( __PACKAGE__ . "::$namespace" )->can('post_process'); };
    if ($post_process_cr) {
        $post_process_cr->( $input_values_h, \%newvalues, \%rejects, \%reject_reasons );
    }

    return wantarray ? ( \%newvalues, \%rejects, \%reject_reasons, \%conflicts ) : \%newvalues;
}

=head2 _check_for_update_conflicts

This function determines if the values for any settings have been modified in cpanel.config
between the time the tweak settings form was loaded, and the time the tweak settings form was
submitted.

=head3 Input

=over 3

=item C<HASH> %ARGS

    A hash containing the following named arguments:

=over 3

=item C<SCALAR> namespace

    The name of the tweak settings module being processed.

=item C<HASHREF> current_conf_values

    A hash reference containing the current cpanel.config values.

=item C<HASHREF> new_values

    A hash reference containing the new cpanel.config values to be saved.

=item C<HASHREF> input_values

    A hash reference containing the values submitted from the tweak settings form. Used to determine the cpanel.config values at the time the tweak settings form was loaded.

=back

=back

=head3 Output

Returns a hash containing any conflicts that were found, along with the conflicting values.

=head3 Exceptions

Throws Cpanel::Exception::MissingParameter if any of the named arguments are missing or invalid.

=cut

sub _check_for_update_conflicts {
    my %ARGS = @_;

    # Ensure expected named args were passed in as hash refs.
    for my $expected_hashref (qw( current_conf_values new_values input_values )) {
        if ( !$ARGS{$expected_hashref} || ref $ARGS{$expected_hashref} ne 'HASH' ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create_raw( 'MissingParameter', qq{$expected_hashref hash reference is required} );
        }
    }

    if ( !defined $ARGS{'namespace'} ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create_raw( 'MissingParameter', qq{Module namespace must be provided.} );
    }

    my %conflicts;
  NEW_VALUE:
    for my $changed_setting ( keys %{ $ARGS{'new_values'} } ) {

        # No value exists in the current config, so there is no conflict.
        next NEW_VALUE unless exists $ARGS{'current_conf_values'}->{$changed_setting};

        my $new_value = $ARGS{'new_values'}->{$changed_setting};

        # State of the cpanel.config at time of submission/update.
        my $current_conf_value = $ARGS{'current_conf_values'}->{$changed_setting};

        # The values from cpanel.config at the time the tweak settings form loaded.
        my $prior_conf_value = $ARGS{'input_values'}->{ '___original_' . $changed_setting };
        my $prior_conf_undef = $ARGS{'input_values'}->{ '___undef_original_' . $changed_setting } ? 1 : 0;

        # Can't check for a conflict...
        next NEW_VALUE unless $prior_conf_undef || defined $prior_conf_value;

        # If nothing has changed in the form submission, check for a conflict.
        if ( $prior_conf_undef && !defined $new_value || ( $new_value // '' ) eq ( $prior_conf_value // '' ) ) {

            # If the value in cpanel.config has changed between the tweak settings form was loading
            # and the changes being submitted, we honor the conf file value over the submitted value,
            # and label the submitted value as a confict.
            if ( _values_differ( $new_value, $current_conf_value ) ) {
                $logger ||= Cpanel::Logger->new();
                $logger->warn("$changed_setting changed in $ARGS{'namespace'} between the tweak page being loaded and saved.");
                $ARGS{'new_values'}->{$changed_setting} = $current_conf_value;
                $conflicts{$changed_setting} = $current_conf_value;
            }
        }
    }

    return %conflicts;
}

=head2 _values_differ

This function determines if the two supplied scalars are different, accounting for definedness in the process
to avoid warnings.

=head3 Input

=over 3

=item C<SCALAR> $value_a

    The first scalar value to compare.

=item C<SCALAR> $value_b

    The second scalar value to compare.

=back

=head3 Output

Returns boolean indicating whether or not the values are different.

=head3 Exceptions

None

=cut

sub _values_differ {
    my ( $value_a, $value_b ) = @_;

    # Value has become undef
    return 1 if !defined $value_a && defined $value_b;

    # Value has become defined
    return 1 if defined $value_a && !defined $value_b;

    # Value remained undef
    return 0 if !defined $value_a && !defined $value_b;

    return $value_a eq $value_b ? 0 : 1;
}

#this is for 'binary' or anything with an 'options' key
#same logic as a checkval function: undef if invalid
#undefined values, thus, should not pass through here
sub validate_setting {
    my ( $setting, $value ) = @_;
    my $setting_type = $setting->{'type'};

    my %valid_options_lookup;
    if ( exists $setting->{'options'} ) {
        if ( ref $setting->{'options'}->[0] eq 'ARRAY' ) {
            %valid_options_lookup = map { $_->[1] => 1, } @{ $setting->{'options'} };
        }
        else {
            %valid_options_lookup = map { $_ => 1, } @{ $setting->{'options'} };
        }
    }
    elsif ( $setting_type eq 'binary' || $setting_type eq 'inversebinary' ) {
        %valid_options_lookup = ( '0' => 1, '1' => 1 );
    }
    else {
        $logger ||= Cpanel::Logger->new();
        $logger->warn("Attempt to run TweakSettings::validate_setting on a setting ($setting->{'key'}) with no defined options");
        return;
    }

    return $valid_options_lookup{$value} ? $value : ();
}

=head2 fill_missing_defaults

This function puts the default value of missing keys into the passed hashref for a specified TweakSettings module.

NOTE: This does not account for required value resolution.

=head3 Input

=over 3

=item C<SCALAR> $module

    The name of the TweakSettings module to fill in the missing default values for. This parameter is case sensitive.

=item C<HASHREF> $settings

    A hashref containing TweakSettings configuration data that will be modified to contain the default values of missing keys.

=back

=head3 Output

Returns $settings by reference.

=head3 Exceptions

Any that get_conf may throw.

=cut

sub fill_missing_defaults {
    my ( $module, $current_settings_ref ) = @_;

    my $conf = get_conf($module);
    for my $key ( keys %$conf ) {
        next if defined $current_settings_ref->{$key};
        next if !defined $conf->{$key}{default};
        next if $conf->{$key}{can_undef};

        $current_settings_ref->{$key} = $conf->{$key}{default};

        # Some keys have a coderef as their default value (Actually it looks like only $Whostmgr::TweakSettings::Apache::Conf{maxclients} as of July 2017)
        if ( 'CODE' eq ref $current_settings_ref->{$key} ) {
            $current_settings_ref->{$key} = $current_settings_ref->{$key}->($current_settings_ref);
        }
    }

    return;
}

#depends on there being a 'value' for the given configuration key
sub get_value {
    my ( $module, $key ) = @_;
    my $conf = get_conf_cached($module) || return;
    $conf = $conf->{$key} || return;
    return if !exists( $conf->{'value'} );

    my $value = $conf->{'value'};
    if ( ref $value && ref $value eq 'CODE' ) {
        Cpanel::LoadModule::load_perl_module("Whostmgr::TweakSettings::Configure::$module");
        my $conf = "Whostmgr::TweakSettings::Configure::$module"->new()->get_conf();
        $value = $value->($conf);
    }

    return $value;
}

sub set_value {
    my ( $module, $key, $new, $old, $force ) = @_;
    my $result = apply_module_settings( $module, { $key => $new } );

    if ( $result->{'rejects'}{$key} ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create_raw( 'InvalidParameter', $result->{'reject_reasons'}{$key} );
    }

    return $result->{'config_hr'}{$key} eq $new ? 1 : 0;
}

sub set_multiple_values {
    my (@values) = @_;
    my $all_ok = 1;      # Assume Success.
    foreach my $entries_ar (@values) {
        my ( $module, $key, $new, $old, $force ) = @{$entries_ar};
        my $result = apply_module_settings( $module, { $key => $new } );
        if ( $result->{'rejects'}{$key} ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create_raw( 'InvalidParameter', $result->{'reject_reasons'}{$key} );
        }
        if ( $result->{'config_hr'}{$key} ne $new ) {
            $all_ok = 0;
        }
    }
    return $all_ok;
}

my %_conf_cache;

sub get_conf_cached {
    return ( $_conf_cache{ $_[0] } ||= get_conf( $_[0] ) );
}

sub load_module {
    my ($conf_type) = @_;

    my $tweak_module = __PACKAGE__ . '::' . $conf_type;
    my $path         = $tweak_module =~ s{::}{/}gr;

    if ( !$INC{"$path.pm"} ) {
        Cpanel::LoadModule::load_perl_module($tweak_module);
    }

    my $init_coderef = "Whostmgr::TweakSettings::$conf_type"->can('init');

    $init_coderef->() if $init_coderef;

    return;
}

sub get_conf {
    my ($conf_type) = @_;

    load_module($conf_type);

    # Run time load of cpanel.config defaults.
    "Whostmgr::TweakSettings::$conf_type"->can('set_defaults')->() if $conf_type eq 'Main';

    my $tweak_module = __PACKAGE__ . '::' . $conf_type;
    my $conf_h;
    {
        no strict 'refs';
        $conf_h = \%{"${tweak_module}::Conf"};
    }
    return wantarray ? %{$conf_h} : $conf_h;
}

sub get_conf_headers {
    my ($conf_type) = @_;

    load_module($conf_type);
    my $tweak_module = __PACKAGE__ . '::' . $conf_type;
    my $conf_headers_h;
    {
        no strict 'refs';
        $conf_headers_h = \%{"${tweak_module}::Conf_headers"};
    }
    return wantarray ? %{$conf_headers_h} : $conf_headers_h;
}

sub get_texts {
    my $tweak_module = shift();
    Cpanel::LoadModule::load_perl_module('Whostmgr::Theme');
    my $texts_file = Whostmgr::Theme::find_file_path("tweaksettings/${tweak_module}.yaml");

    Cpanel::LoadModule::load_perl_module('Cpanel::CachedDataStore');

    my $ref = Cpanel::CachedDataStore::fetch_ref($texts_file);

    if ( $tweak_module eq 'Basic' ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::iContact::Providers');
        Cpanel::iContact::Providers::augment_tweak_texts($ref);
    }

    return $ref;
}

sub apply_module_settings {
    my ( $module, $key_value_pairs, $force, $module_opts ) = @_;

    return apply_module_settings_with_template_output(
        $module,
        $key_value_pairs,
        $force,
        $module_opts,
        {
            'template_coderef' => sub { },
            'redirect_stdout'  => 1,
        }
    );
}

sub apply_module_settings_with_template_output {
    my ( $module, $key_value_pairs, $force, $module_opts, $config_opts ) = @_;

    $force //= 0;
    $key_value_pairs ||= {};    # called from --updatetweaksettings
    $module_opts     ||= {};

    Cpanel::Validate::FilesystemNodeName::validate_or_die($module);

    my $namespace = "Whostmgr::TweakSettings::Configure::$module";

    Cpanel::LoadModule::load_perl_module($namespace);

    my $configure_object = $namespace->new(%$module_opts);

    my $conf_hr = $configure_object->get_conf() or return;

    my $old_config_hr = $configure_object->get_original_conf();

    $configure_object->pre_process($key_value_pairs);

    my ( $new_config_hr, $rejects_hr, $reject_reasons_hr ) = process_input_values(
        $module,
        $key_value_pairs,
        $old_config_hr
    );

    if ( !defined $new_config_hr ) {
        $configure_object->abort();
        return {
            'modified'       => 0,
            'config_hr'      => $old_config_hr,
            'rejects'        => $rejects_hr,
            'reject_reasons' => $reject_reasons_hr,
        };
    }
    foreach my $key ( sort keys %$rejects_hr ) {
        if ( exists $old_config_hr->{$key} && exists $key_value_pairs->{$key} ) {
            if ( index( $reject_reasons_hr->{$key}, "$key requires " ) != 0 ) {

                # X requires Y is not a useful warning and only serves to confuse users
                # as such we now suppress it.
                Cpanel::Debug::log_warn("Invalid value ($rejects_hr->{$key}) for $key [$reject_reasons_hr->{$key}]. This setting will not be updated.");
            }
            $new_config_hr->{$key} = $old_config_hr->{$key};
        }
    }

    require Whostmgr::Config;

    #calls the template to finish up the screen
    my ( $status, $retref, $failed_updates ) = Whostmgr::Config::apply_tweaks(
        'newvalues'      => $new_config_hr,
        'module'         => $module,
        'rejects'        => $rejects_hr,
        'conf_ref'       => $old_config_hr,
        'force'          => $force,
        'reject_reasons' => $reject_reasons_hr,
        %$config_opts,
    );
    if ( !$status ) {
        Cpanel::Debug::log_warn("The system failed to apply the settings for the “$module”.");
        $configure_object->abort();
        return $old_config_hr;
    }

    foreach my $key ( @{$failed_updates} ) {
        Cpanel::Debug::log_warn("Action for $key failed to update value ($rejects_hr->{$key}). This setting will not be updated.");
        $new_config_hr->{$key} = $old_config_hr->{$key};
    }

    # Only set values that have actually been passed in
    # For legacy compat with the TweakSettings screen in
    # WHM we have to check for the _control and _other
    # keys
    foreach my $key ( keys %$new_config_hr ) {
        next if !grep { defined } @{$key_value_pairs}{ _possible_key_names($key) };
        $configure_object->set( $key, $new_config_hr->{$key} );
    }

    if ( !$configure_object->save() ) {
        $configure_object->abort();
        return {
            'modified'       => 0,
            'config_hr'      => $old_config_hr,
            'rejects'        => $rejects_hr,
            'reject_reasons' => $reject_reasons_hr,
        };
    }

    # These actions need to happen after the new config is updated
    Whostmgr::Config::post_apply_tweaks(
        ref $retref ? %{$retref} : ( 'post_actions' => [] ),
        %$config_opts,
    );

    $configure_object->finish();

    return {
        'modified' => 1,

        'config_hr'      => $configure_object->get_conf(),
        'rejects'        => $rejects_hr,
        'reject_reasons' => $reject_reasons_hr,
    };
}

# The TweakSettings UI submits as a plain HTML form submission and so
# uses some pretty “retro” techniques to indicate the intended value
# of a field. For example, if the UI presents “thething”’s values
# as a set # of radio buttons, the value will be given in the form’s
# “thething_control” value. Likewise, if one of those radio buttons
# enables a free-form text input, that text input will be sent in the
# HTML form submission as “thething_other”, not as “thething”.
#
sub _possible_key_names {

    # IMPORTANT!! Order matters: higher priority goes to LATER names.
    return ( $_[0], "$_[0]_control", "$_[0]_other" );
}

sub _has_required_setting {
    my $args_ref           = shift;
    my $required_setting   = $args_ref->{'required_setting'} || return 1;
    my $input_values_ref   = $args_ref->{'input'}            || {};
    my $current_config_ref = $args_ref->{'current_config'}   || {};

    # We don't need to validate requirements if we're disabling the destination setting.
    if ( !$input_values_ref->{ $args_ref->{'setting'} } ) {
        return 1;
    }

    my $required_setting_input;
    for my $key ( _possible_key_names($required_setting) ) {
        if ( defined $input_values_ref->{$key} ) {
            $required_setting_input = $input_values_ref->{$key};
        }
    }

    # Validate if the required setting field was provided.
    if ( $required_setting && $required_setting_input ) {
        return 1;
    }

    # Validate if required setting is enabled in current config, and isn't being set with new input values
    elsif ( $current_config_ref->{$required_setting} && !defined $required_setting_input ) {
        return 1;
    }

    # Validate if required setting isn't in current config, but is enabled in input values
    elsif ( !defined $current_config_ref->{$required_setting} && $required_setting_input ) {
        return 1;
    }
    elsif ( !$current_config_ref->{$required_setting} && !$required_setting_input ) {
        return 0;
    }

    # Invalidate otherwise.
    return 0;
}

1;
