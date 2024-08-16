
# cpanel - Whostmgr/ModSecurity/Settings.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::Settings;

use strict;
use warnings;

use Cpanel::Locale::Lazy 'lh';
use Whostmgr::ModSecurity::ModsecCpanelConf ();
use Whostmgr::ModSecurity::TransactionLog   ();
use Whostmgr::ModSecurity                   ();

=head1 NAME

Whostmgr::ModSecurity::Settings

=head1 DESCRIPTION

This module is for configuring settings that impact the global behavior of mod_security
rather than individual rules. (Whostmgr::ModSecurity::Configure is for rules.)

=head1 SETTING TYPES

=head2 text

A setting for a directive that takes a single string as its argument which
is best freeform edited by the user rather than constrainted to a set of options.

=head2 radio

A setting for a directive which takes a certain set of possible values
for its argument, and which is best presented as a set of radio buttons.

=head1 CONFIGURABLE SETINGS

The following settings are configurable through this module:

  SecAuditEngine
  SecConnEngine
  SecDisableBackendCompression
  SecGeoLookupDb
  SecGsbLookupDb
  SecGuardianLog
  SecHttpBlKey
  SecPcreMatchLimit
  SecPcreMatchLimitRecursion
  SecRuleEngine

=cut

sub known_settings {

    my $version = Whostmgr::ModSecurity::version();

    if ( !$version ) {
        die "Could not determine mod security version";
    }

    my ($major_version) = $version =~ m{^(\d+)\.\d+};

    my $BASE_URL = "https://github.com/SpiderLabs/ModSecurity/wiki/Reference-Manual-%28v${major_version}.x%29";    # Don't change this to a go.cpanel.net URL. See case 117165.

    return (
        {
            name          => lh()->maketext('Audit Log Level'),
            directive     => 'SecAuditEngine',
            type          => 'radio',
            radio_options => [
                { option => 'On',           name => lh()->maketext('Log all transactions.') },
                { option => 'Off',          name => lh()->maketext('Do not log any transactions.') },
                { option => 'RelevantOnly', name => lh()->maketext('Only log noteworthy transactions.') },
            ],
            extract_args => \&_extract_arbitrary_arguments,
            default      => 'Off',
            our_default  => 'RelevantOnly',
            engine       => 1,
            url          => $BASE_URL . '#secauditengine',
            description  => lh()->maketext('This setting controls the behavior of the audit engine.'),
        },
        {
            name          => lh()->maketext('Connections Engine'),
            directive     => 'SecConnEngine',
            type          => 'radio',
            radio_options => [
                { option => 'On',            name => lh()->maketext('Process the rules.') },
                { option => 'Off',           name => lh()->maketext('Do not process the rules.') },
                { option => 'DetectionOnly', name => lh()->maketext('Process the rules in verbose mode, but do not execute disruptive actions.') },
            ],
            extract_args => \&_extract_arbitrary_arguments,
            engine       => 1,
            default      => 'Off',                                                                             #This is a guess based on the documentation, it may be wrong.
            url          => $BASE_URL . '#secconnengine',
            description  => lh()->maketext('This setting controls the behavior of the connections engine.'),
        },
        {
            name          => lh()->maketext('Rules Engine'),
            directive     => 'SecRuleEngine',
            type          => 'radio',
            radio_options => [
                { option => 'On',            name => lh()->maketext('Process the rules.') },
                { option => 'Off',           name => lh()->maketext('Do not process the rules.') },
                { option => 'DetectionOnly', name => lh()->maketext('Process the rules in verbose mode, but do not execute disruptive actions.') },
            ],
            extract_args => \&_extract_arbitrary_arguments,
            default      => 'Off',
            our_default  => 'On',
            engine       => 1,
            url          => $BASE_URL . '#secruleengine',
            description  => lh()->maketext('This setting controls the behavior of the rules engine.'),
        },
        {
            name          => lh()->maketext('Backend Compression'),
            directive     => 'SecDisableBackendCompression',
            type          => 'radio',
            radio_options => [
                { option => 'On',  name => lh()->maketext('Disabled') },    # On means "Disabled" because this directive disables backend compression when On
                { option => 'Off', name => lh()->maketext('Enabled') },
            ],
            default      => 'Off',
            extract_args => \&_extract_arbitrary_arguments,
            url          => $BASE_URL . '#secdisablebackendcompression',
            description  => lh()->maketext('Disables backend compression while leaving the frontend compression enabled.'),
        },
        {
            name            => lh()->maketext('Geolocation Database'),
            directive       => 'SecGeoLookupDb',
            type            => 'text',
            validation      => ['path'],
            extract_args    => \&_extract_arbitrary_arguments,
            delete_if_undef => 1,
            url             => $BASE_URL . '#secgeolookupdb',
            description     => lh()->maketext('Specify a path for the geolocation database.'),
        },
        {
            name            => lh()->maketext('[asis,Google Safe Browsing] Database'),
            directive       => 'SecGsbLookupDb',
            type            => 'text',
            validation      => ['path'],
            extract_args    => \&_extract_arbitrary_arguments,
            delete_if_undef => 1,
            url             => $BASE_URL . '#secgsblookupdb',
            description     => lh()->maketext('Specify a path for the [asis,Google Safe Browsing] Database.'),
        },
        {
            name       => lh()->maketext('Guardian Log'),
            directive  => 'SecGuardianLog',
            type       => 'text',
            validation => [
                { name => 'startsWith', arg => '[|]' },
                'path',
            ],    # |path to gardian
            extract_args    => \&_extract_arbitrary_arguments,
            delete_if_undef => 1,
            url             => $BASE_URL . '#secguardianlog',
            description     => lh()->maketext('Specify an external program to pipe transaction log information to for additional analysis. The syntax is analogous to the [asis,.forward] file, in which a pipe at the beginning of the field indicates piping to an external program.'),
        },
        {
            name            => lh()->maketext('[asis,Project Honey Pot Http:BL API Key]'),
            directive       => 'SecHttpBlKey',
            type            => 'text',
            validation      => ['honeypotAccessKey'],                                                                                 #http://www.projecthoneypot.org/httpbl_api.php - All Access Keys are 12-characters in length, lower case, and contain only alpha characters (no numbers)
            extract_args    => \&_extract_arbitrary_arguments,
            delete_if_undef => 1,
            url             => $BASE_URL . '#sechttpblkey',
            description     => lh()->maketext('Specify a [asis,Project Honey Pot API Key] for use with the [asis,@rbl] operator.'),
        },
        {
            name         => lh()->maketext('[asis,Perl Compatible Regular Expressions] Library Match Limit'),
            directive    => 'SecPcreMatchLimit',
            type         => 'number',
            validation   => ['positiveInteger'],
            extract_args => \&_extract_arbitrary_arguments,
            default      => 1500,
            url          => $BASE_URL . '#secpcrematchlimit',
            description  => lh()->maketext('Define the match limit of the [asis,Perl Compatible Regular Expressions] library.'),
        },
        {
            name         => lh()->maketext('[asis,Perl Compatible Regular Expressions] Library Match Limit Recursion'),
            directive    => 'SecPcreMatchLimitRecursion',
            type         => 'number',
            validation   => ['positiveInteger'],
            extract_args => \&_extract_arbitrary_arguments,
            default      => 1500,
            url          => $BASE_URL . '#secpcrematchlimitrecursion',
            description  => lh()->maketext('Define the match limit recursion of the [asis,Perl Compatible Regular Expressions] library.'),
        },
    );
}

sub _lookup_setting_by_id {
    my ($setting_id)   = @_;
    my $n              = 0;
    my ($setting_info) = grep { $n++ eq $setting_id } known_settings();
    if ( !$setting_info ) {

        # If this error occurs when passign in a setting_id provided by modsec_get_settings, then there may be a bug.
        # If this happens across updates, and it was due to ids shifting, then the solution is to refresh the page
        # before trying again.
        die lh()->maketext( q{This feature cannot manage the “[_1]” [asis,setting_id] value.}, $setting_id ) . "\n";
    }
    return $setting_info;
}

=head1 SUBROUTINES

=head2 get_settings()

=head3 Description

Retrieves a list of configurable mod_security settings along with their current values.
Settings which are configurable but not present in modsec2.conf will be noted as such.

=head3 Arguments

None

=head3 Returns

The function returns an array ref of settings. Each setting is a hash ref containing
the following:

  'setting_id' : A unique identifier the caller may use to pick out an individual setting.
        'name' : The (possibly localized) name of the setting.
        'type' : The type of UI control that fits this setting best.
     'missing' : If true, the setting is not present in modsec2.conf at all.
       'state' : The current state of the setting.
   'directive' : ModSecurity directive name.
         'url' : Url where you can find more information on the directive.
 'description' : Description of what the setting is used for.
  'validation' : Optional array of validation rules and optional arguments to the rules
     'default' : Optional default value, used if not set.
      'engine' : Optional boolean if 1 means the rule is an engine, otherwise its just a normal directive. Engines have special handing in the UI.

Additionally, only for radio buttons:

 'radio_options': A hash ref containing key/value pairs mapping a state name to a localized option name.

=cut

my @response_format = qw(setting_id name type radio_options missing state directive url description validation default engine);

sub get_settings {
    my @settings = known_settings();

    my $mcc                 = Whostmgr::ModSecurity::ModsecCpanelConf->new();
    my $configured_settings = $mcc->inspect(
        sub {
            my $data = shift;
            return {
                %{ $data->{settings}         || {} },
                %{ $data->{pending_settings} || {} },
            };
        }
    );

    for my $setting_id ( 0 .. $#settings ) {

        my $setting = $settings[$setting_id];
        $setting->{setting_id} = $setting_id;

        my $configured_value = $configured_settings->{ $setting->{directive} };
        if ( defined $configured_value ) {
            $setting->{state} = $configured_value;
        }
        else {
            $setting->{state}   = '';
            $setting->{missing} = 1;
        }

        for my $k ( keys %$setting ) {
            delete $setting->{$k} if !grep { $_ eq $k } @response_format;
        }
    }

    return \@settings;
}

=head2 set_setting

=head3 Description

Adjust a mod_security setting in modsec2.conf. If the directive corresponding to this setting
is already present, it will be amended. Otherwise, it will be added to the end of the file.

B<IMPORTANT:> Any changes that this function makes will be ineffective
until the next C<deploy_settings_changes()> call.

=head3 Arguments

This function takes two arguments:

  - The setting_id of the setting (as reported by get_settings). Not to be confused with rule ids, which are unrelated.
  - The new value/state for the setting.

=head3 Returns

This function returns a true value upon success.

=cut

sub set_setting {
    my ( $setting_id, $setting_value ) = @_;

    my $setting_info = _lookup_setting_by_id($setting_id);

    if ( $setting_info->{radio_options} && !_radio_option_exists_in( $setting_info, $setting_value ) ) {
        die lh()->maketext( q{The following value is not valid for the “[_1]” setting: [_2]}, $setting_info->{name}, $setting_value ) . "\n";
    }

    my $mcc    = Whostmgr::ModSecurity::ModsecCpanelConf->new( skip_restart => 1 );
    my @result = $mcc->manipulate(
        sub {
            my $data = shift;
            $data->{pending_settings}{ $setting_info->{directive} } = $setting_value;
        }
    );
    Whostmgr::ModSecurity::TransactionLog::log( operation => 'set_setting', arguments => { directive => $setting_info->{directive}, value => $setting_value } );
    return @result;
}

=head2 remove_setting

=head3 Description

Remove any occurrence of the directive for a mod_security setting from modsec2.conf.

B<IMPORTANT:> Any changes that this function makes will be ineffective
until the next C<deploy_settings_changes()> call.

=head3 Argumentts

  - The numeric setting_id as reported by get_settings.

=head3 Returns

This function returns a true value upon success.

=cut

sub remove_setting {
    my ($setting_id) = @_;

    my $setting_info = _lookup_setting_by_id($setting_id);

    my $mcc    = Whostmgr::ModSecurity::ModsecCpanelConf->new( skip_restart => 1 );
    my @result = $mcc->manipulate(
        sub {
            my $data = shift;

            # The presence of a key/value pair in pending_settings in which the key
            # matches the directive name and the value is undef will cause the setting's
            # value to be replaced with undef in 'settings', which will in turn cause
            # it to be removed.
            $data->{pending_settings}{ $setting_info->{directive} } = undef;
        }
    );
    Whostmgr::ModSecurity::TransactionLog::log( operation => 'remove_setting', arguments => { directive => $setting_info->{directive} } );
    return @result;
}

sub deploy_settings_changes {
    my $mcc    = Whostmgr::ModSecurity::ModsecCpanelConf->new();
    my @result = $mcc->manipulate(
        sub {
            my $data = shift;

            $data->{settings} = {
                %{ $data->{settings} || {} },
                %{ delete( $data->{pending_settings} ) || {} },
            };

            for ( keys %{ $data->{settings} } ) {
                delete $data->{settings}{$_} if !defined $data->{settings}{$_};
            }
        }
    );
    Whostmgr::ModSecurity::TransactionLog::log( operation => 'deploy_settings_changes', arguments => [] );
    return @result;
}

# Examples of the types of things that need to work:
#   ExampleDirective Off
#   ExampleDirective "foo bar"
#   ExampleDirective 'foo bar'
#   ExampleDirective 50 'foo bar' 60 "one \"two\" three" /usr/local/foo/bar.conf
sub _extract_arbitrary_arguments {
    my ($args_str) = @_;
    my @arguments;
    my $this_argument;
    do {
        $this_argument = undef;
        if ( $args_str =~ s{^"((?:\\"|[^"])+)"\s*}{} ) {    # A double quoted string, possibly including spaces and escaped double quotes
            $this_argument = $1;
        }
        elsif ( $args_str =~ s{^'((?:\\'|[^'])+)'\s*}{} ) {    # A single quoted string, possibly etc.
            $this_argument = $1;
        }
        elsif ( $args_str =~ s{^([^"']\S*)\s*}{} ) {           # An unquoted string with no spaces
            $this_argument = $1;
        }
    } while ( defined($this_argument) && push( @arguments, $this_argument ) );

    if ( length $args_str ) {
        die lh()->maketext( q{The system could not extract all of the arguments from the directive. The remaining portion does not conform to the expected syntax: [_1]}, $args_str ) . "\n";
    }

    return @arguments;
}

# Do the equivalent of checking a hash key, in a flat array of key/value pairs.
sub _radio_option_exists_in {
    my ( $setting_info, $setting_value ) = @_;
    ref $setting_info eq 'HASH' or die;
    return if !defined($setting_value) || !$setting_info->{radio_options};
    for my $ro ( @{ $setting_info->{radio_options} } ) {
        return 1 if $ro->{option} eq $setting_value;
    }
    return;
}

1;
