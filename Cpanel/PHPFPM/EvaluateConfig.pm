package Cpanel::PHPFPM::EvaluateConfig;

# cpanel - Cpanel/PHPFPM/EvaluateConfig.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::CachedDataStore             ();
use Cpanel::Config::LoadUserDomains     ();
use Cpanel::Config::userdata::Constants ();
use Cpanel::FileUtils::Write            ();
use Cpanel::PHP::Config                 ();
use Cpanel::PHPFPM                      ();
use Cpanel::PHPFPM::Constants           ();
use Cpanel::ProgLang                    ();
use Cpanel::Validate::Domain            ();
use Cpanel::Locale                      ();

use List::Util ();

our $locale;

=pod

=head1 NAME

Cpanel::PHPFPM::EvaluateConfig

=head1 DESCRIPTION

This module provides functionality to evaluate php fpm configurations.

=head1 FUNCTIONS

=cut

=head2 _output_pool_conf_to_tempfile

Parameters are:

$domain_hr which is generated evaluate_pool_config, either directly
or from Cpanel::PHP::Config::get_php_config_for_domains.

This will create a php pool ini config file and output it
to the $tempfile from the arguments.

=cut

sub _output_pool_conf_to_tempfile {
    my ( $domain_hr, $tempfile ) = @_;

    my $output = Cpanel::PHPFPM::_prepare_pool_conf($domain_hr);
    return 0 if !defined $output;

    Cpanel::FileUtils::Write::overwrite( $tempfile, $output, 0777 );
    return 1;
}

=head2 _output_pool_conf_to_tempfile

Parameters:

$domain: the domain name such as example.com, or blank if you want
to test it as the system pool defaults

$yaml_config_to_test: a yaml config file to test the contents of

$optional_php_config_file: if you pass this parameter the php ini config
file will be output to this file.   If you do not pass it, the php ini config
file will be output to a temp file that will be removed after the operation
completes.   By setting this you can inspect the output file.

=cut

sub evaluate_pool_config {
    my ( $domain, $yaml_config_to_test, $optional_php_config_file ) = @_;

    my $domain_hr;

    $locale //= Cpanel::Locale->get_handle();

    require Cpanel::TempFile;

    my $tf    = Cpanel::TempFile->new();
    my $dpath = $tf->dir();

    if ( $domain ne '' ) {
        my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_domains( [$domain] );
        $domain_hr = $php_config_ref->{$domain};
        $domain_hr->{'config_fname'} = $yaml_config_to_test;
    }
    else {
        my $php         = Cpanel::ProgLang->new( type => 'php' );
        my $php_version = $php->get_system_default_package();

        my $userdata_dir = $dpath . '/userdata';
        mkdir $userdata_dir;

        my $docroot = $dpath . '/docroot';
        mkdir $docroot;

        $domain = 'ineedadomainthatdoesntexist.tld';
        my $scrubbed_domain = $domain;
        $scrubbed_domain =~ s/\./_/g;

        $domain_hr = bless {
            'scrubbed_domain'   => $scrubbed_domain,
            'domain'            => $domain,
            'username'          => 'root',
            'owner'             => 'root',
            'userdata_dir'      => $userdata_dir,
            'config_fname'      => $yaml_config_to_test,
            'domain_type'       => 'main',
            'phpversion'        => $php_version,
            'phpversion_source' => { 'domain' => $domain },

            # I would like this to be deprecated
            'phpversion_or_inherit' => $php_version,
            'documentroot'          => $docroot,
            'homedir'               => $dpath,
          },
          'Cpanel::PHP::Config::Domain';
    }

    my $tempfile = $dpath . '/myfpm.conf';
    $tempfile = $optional_php_config_file if ( defined $optional_php_config_file );

    my $ret = _output_pool_conf_to_tempfile( $domain_hr, $tempfile );
    if ( $ret eq "0" ) {
        return {
            'Status' => 0,
            'Error'  => $locale->maketext('The system encountered an error. Check your configuration and try again.'),
        };
    }

    # now we need to see if it works

    my $fpm_executable = $Cpanel::PHPFPM::Constants::opt_cpanel . '/' . $domain_hr->{'phpversion'} . "/root/usr/sbin/php-fpm";

    require Cpanel::SafeRun::Full;

    my @cmd = ( '-R', '-t', '-y', $tempfile );

    my $result_hr = Cpanel::SafeRun::Full::run(
        'program' => $fpm_executable,
        'args'    => \@cmd,
    );

    # I'm reusing the string from Cpanel::Exception::ProcessFailed::Error here
    if ( $result_hr->{'exit_value'} != 0 ) {
        return {
            'Status' => 0,
            'Error'  => $locale->maketext(
                "“[_1]” reported error code “[_2]” when it ended: [_3]",
                $fpm_executable,
                $result_hr->{'exit_value'},
                ( $result_hr->{'stdout'} // '' ) . ( $result_hr->{'stderr'} // '' ),
            ),
        };
    }
    else {
        return {
            'Status' => 1,
            'Error'  => $locale->maketext('Success! The configuration is correct.'),
        };
    }
}

=head2 generate_temp_yaml_config

Parameters are:

$temp_yaml_file - where to output the resulting yaml file

$params - an array ref, of each parameter to add to the yaml file
          it is an array of hashs

          {
            'trinary_admin_value' => 0, 1, or 2    # 0 means no, 1 means php_admin_value or php_admin_flag, 2 means php_value
                                                   # NOTE: it is an error if you set it to 0 and the default
                                                   # value is either # php_admin_value or # php_value
            'base_flag_name' => 'error_reporting'  # NOTE: it should NOT have php_admin_value or php_value around it
            'value' => value                       # the value to set it to
          }

Returns a hash ref

{
    'Status' => 1 success or 0 fail
    'Message' => a message regarding status
}

Output is a yaml file that is built from the passed in values

=cut

sub generate_temp_yaml_config {
    my ( $temp_yaml_file, $params, $existing_yaml_hr ) = @_;

    $locale //= Cpanel::Locale->get_handle();

    my $yaml_config = [];

    foreach my $record ( @{$params} ) {

        # does this exist as itself, php_value, php_admin_value or
        # php_admin_flag

        my $name                 = $record->{'base_flag_name'};
        my $php_admin_value_name = 'php_admin_value_' . $name;
        my $php_admin_flag_name  = 'php_admin_flag_' . $name;
        my $php_value_name       = 'php_value_' . $name;
        my $php_flag_name        = 'php_flag_' . $name;

        if (   $record->{'trinary_admin_value'} != 0
            && $record->{'trinary_admin_value'} != 1
            && $record->{'trinary_admin_value'} != 2 ) {
            return {
                'Status'  => 0,
                'Message' => $locale->maketext('Invalid [asis,trinary_admin_value] parameter value. The value must be 0, 1, or 2.'),
            };
        }

        if ( exists $Cpanel::PHPFPM::php_fpm_pool_directives{$name} ) {

            # This parameter is not php_value or php_admin_value

            if ( $record->{'trinary_admin_value'} != 0 ) {
                return {
                    'Status'  => 0,
                    'Message' => $locale->maketext('This parameter only allows a [asis,trinary_admin_value] value of 0.'),
                };
            }

            push(
                @{$yaml_config},
                {
                    'name'  => $name,
                    'value' => $record->{'value'},
                }
            );
        }
        elsif ( exists $Cpanel::PHPFPM::php_fpm_pool_directives{$php_value_name} ) {

            # This parameter is a php_value

            if ( $record->{'trinary_admin_value'} == 0 ) {

                # if the parameter is already listed as a php_value or
                # php_admin_value, it cannot stand on it's own in the config
                # file
                return {
                    'Status'  => 0,
                    'Message' => $locale->maketext('This parameter only allows a [asis,trinary_admin_value] value of 1 or 2.'),
                };
            }

            if ( $record->{'trinary_admin_value'} != 2 ) {

                # we need to change it's type
                # First do a remove of the value as a php_value

                push(
                    @{$yaml_config},
                    {
                        'name'  => $php_value_name,
                        'value' => {
                            'present_ifdefault' => 0,
                        }
                    }
                );

                # Now add it as a php_admin_value

                push(
                    @{$yaml_config},
                    {
                        'name'  => $php_admin_value_name,
                        'value' => {
                            'present_ifdefault' => 1,
                            'name'              => "php_admin_value[$name]",
                            'value'             => $record->{'value'},
                        }
                    }
                );
            }
            else {
                # type has not changed, so just change the value
                push(
                    @{$yaml_config},
                    {
                        'name'  => $php_value_name,
                        'value' => $record->{'value'},
                    }
                );
            }
        }
        elsif (exists $Cpanel::PHPFPM::php_fpm_pool_directives{$php_admin_value_name}
            || exists $Cpanel::PHPFPM::php_fpm_pool_directives{$php_admin_flag_name} ) {

            # This parameter is a php_admin_value or php_admin_flag
            if ( $record->{'trinary_admin_value'} == 0 ) {

                # if the parameter is already listed as a php_value or
                # php_admin_value, it cannot stand on it's own in the config
                # file
                return {
                    'Status'  => 0,
                    'Message' => $locale->maketext('This parameter only allows a [asis,trinary_admin_value] value of 1 or 2.'),
                };
            }

            # which is it, admin_value or admin_flag?
            my $this_name = $php_admin_value_name;
            $this_name = $php_admin_flag_name if ( exists $Cpanel::PHPFPM::php_fpm_pool_directives{$php_admin_flag_name} );

            if ( $record->{'trinary_admin_value'} != 1 ) {

                # we need to change it's status, so we first remove the
                # existing record

                push(
                    @{$yaml_config},
                    {
                        'name'  => $this_name,
                        'value' => {
                            'present_ifdefault' => 0,
                        }
                    }
                );

                my $new_name   = $php_value_name;
                my $value_name = "php_value[$name]";
                if ( exists $Cpanel::PHPFPM::php_fpm_pool_directives{$php_admin_flag_name} ) {
                    $new_name   = $php_flag_name;
                    $value_name = "php_flag[$name]";
                }

                # and now change it to a php_value
                push(
                    @{$yaml_config},
                    {
                        'name'  => $new_name,
                        'value' => {
                            'present_ifdefault' => 1,
                            'name'              => $value_name,
                            'value'             => $record->{'value'},
                        }
                    }
                );
            }
            else {
                push(
                    @{$yaml_config},
                    {
                        'name'  => $this_name,
                        'value' => $record->{'value'},
                    }
                );
            }
        }
        else {
            return {
                'Status'  => 0,
                'Message' => $locale->maketext( "The system does not recognize the “[_1]” parameter.", $name ),
            };
        }
    }

    my $hash_ref = {};
    foreach my $record ( @{$yaml_config} ) {
        $hash_ref->{ $record->{'name'} } = $record->{'value'};
    }

    # now merge in any existing_yaml_hr entries
    foreach my $key ( sort keys %{$existing_yaml_hr} ) {
        $hash_ref->{$key} = $existing_yaml_hr->{$key};
    }

    Cpanel::CachedDataStore::store_ref( $temp_yaml_file, $hash_ref, { mode => $Cpanel::PHPFPM::USER_PHP_FPM_CONFIG_PERMS } );

    return {
        'Status'  => 1,
        'Message' => $locale->maketext('Successful'),
    };
}

my @_config_parms = qw(pm_max_children pm_max_requests pm_process_idle_timeout allow_url_fopen log_errors disable_functions doc_root error_log short_open_tag error_reporting);

=head2 _config_cpanel_defaults_normalizer

There are no parameters.

This function returns a hash_ref, in the normalized form, of the values in the cPanel defaults for the (@_config_parms).

See _normalize_config for full definition of normalized form.

=cut

sub _config_cpanel_defaults_normalizer {
    my $defaults_hr = {};

    foreach my $name (@_config_parms) {
        my $php_value_name       = 'php_value_' . $name;
        my $php_flag_name        = 'php_flag_' . $name;
        my $php_admin_value_name = 'php_admin_value_' . $name;
        my $php_admin_flag_name  = 'php_admin_flag_' . $name;

        my $ref = {
            'base_flag_name' => $name,
            'is_flag'        => 0,
        };

        if ( exists $Cpanel::PHPFPM::php_fpm_pool_directives{$php_admin_value_name} ) {
            $ref->{'trinary_admin_value'} = 1;
            $ref->{'value'}               = $Cpanel::PHPFPM::php_fpm_pool_directives{$php_admin_value_name}->{'default'};
            $ref->{'default_name'}        = $php_admin_value_name;
        }
        elsif ( exists $Cpanel::PHPFPM::php_fpm_pool_directives{$php_admin_flag_name} ) {
            $ref->{'trinary_admin_value'} = 1;
            $ref->{'value'}               = $Cpanel::PHPFPM::php_fpm_pool_directives{$php_admin_flag_name}->{'default'};
            $ref->{'default_name'}        = $php_admin_flag_name;
            $ref->{'is_flag'}             = 1;
        }
        elsif ( exists $Cpanel::PHPFPM::php_fpm_pool_directives{$php_value_name} ) {
            $ref->{'trinary_admin_value'} = 2;
            $ref->{'value'}               = $Cpanel::PHPFPM::php_fpm_pool_directives{$php_value_name}->{'default'};
            $ref->{'default_name'}        = $php_value_name;
        }
        elsif ( exists $Cpanel::PHPFPM::php_fpm_pool_directives{$php_flag_name} ) {
            $ref->{'trinary_admin_value'} = 2;
            $ref->{'value'}               = $Cpanel::PHPFPM::php_fpm_pool_directives{$php_flag_name}->{'default'};
            $ref->{'default_name'}        = $php_flag_name;
            $ref->{'is_flag'}             = 1;
        }
        elsif ( exists $Cpanel::PHPFPM::php_fpm_pool_directives{$name} ) {
            $ref->{'trinary_admin_value'} = 0;
            $ref->{'value'}               = $Cpanel::PHPFPM::php_fpm_pool_directives{$name}->{'default'};
            $ref->{'default_name'}        = $name;
        }

        $defaults_hr->{$name} = $ref;
    }

    return $defaults_hr;
}

=head2 _get_value

Parameter:

$item - a hashref that has a value from a yaml file.

Pass in a record from the yaml file.  If the item is just a value it returns that value.
If on the other hand the item is a hashref, get the value from that hashref.

This function returns the item's value as a scalar.

Note:

If we see a hashref, then this may be an "add" record in the yaml file.
like: php_admin_value_error_reporting: { name: 'php_admin_value[error_reporting]', value: 'E_ALL & ~E_NOTICE' }

So reach in and get the value.

=cut

sub _get_value {
    my ($item) = @_;

    return $item->{'value'} if ( ref $item eq "HASH" && exists $item->{'value'} );
    return $item;
}

=head2 _check_value

Determine if this hashref is a "remove record" or not.

Parameters:

$generic_hr - A non normalized form of the data out of a yaml file that corresponds to an FPM config.

$value_name - The item in that above hashref we are looking for.

Evaluate if this value in the generic hashref is a "remove record".  If it is a remove record
it will have a value called present_ifdefault and it will be set to zero.

So if it is a remove record, return 0
Otherwise return 1

=cut

sub _check_value {
    my ( $generic_hr, $value_name ) = @_;

    if ( exists $generic_hr->{$value_name} ) {
        if ( ref( $generic_hr->{$value_name} ) eq 'HASH' ) {

            # do not accept value if there is a present_ifdefault subvalue
            # and it is zero, that is for removing a cPanel default value
            if ( exists $generic_hr->{$value_name}->{'present_ifdefault'} ) {
                return 0 if $generic_hr->{$value_name}->{'present_ifdefault'} == 0;
            }
        }

        return 1;
    }

    return 0;
}

=head2 _config_generic_normalizer

Evaluate a hashref that comes from a yaml file.
Create the normalized form of the fpm config from that yaml file.

Parameter:

$generic_hr - A non normalized form of the data out of a yaml file that corresponds to an FPM config.
This form is like the following:

{
    "pm_max_children" => 12,
    "pm_max_requests" => 32
}

Returns a normalized version of that yaml config.

See _normalize_config for full definition of normalized form.

=cut

sub _config_generic_normalizer {
    my ($generic_hr) = @_;

    my $defaults_hr = {};

    foreach my $name (@_config_parms) {
        my $php_value_name       = 'php_value_' . $name;
        my $php_flag_name        = 'php_flag_' . $name;
        my $php_admin_value_name = 'php_admin_value_' . $name;
        my $php_admin_flag_name  = 'php_admin_flag_' . $name;

        my $ref = {
            'base_flag_name' => $name,
            'is_flag'        => 0,
        };

        # we will ignore a "removal" instruction and instead look for a real
        # value

        if ( _check_value( $generic_hr, $php_admin_value_name ) ) {
            $ref->{'trinary_admin_value'} = 1;
            $ref->{'value'}               = _get_value( $generic_hr->{$php_admin_value_name} );
            $ref->{'default_name'}        = $php_admin_value_name;
        }
        elsif ( _check_value( $generic_hr, $php_admin_flag_name ) ) {
            $ref->{'trinary_admin_value'} = 1;
            $ref->{'value'}               = _get_value( $generic_hr->{$php_admin_flag_name} );
            $ref->{'default_name'}        = $php_admin_flag_name;
            $ref->{'is_flag'}             = 1;
        }
        elsif ( _check_value( $generic_hr, $php_value_name ) ) {
            $ref->{'trinary_admin_value'} = 2;
            $ref->{'value'}               = _get_value( $generic_hr->{$php_value_name} );
            $ref->{'default_name'}        = $php_value_name;
        }
        elsif ( _check_value( $generic_hr, $php_flag_name ) ) {
            $ref->{'trinary_admin_value'} = 2;
            $ref->{'value'}               = _get_value( $generic_hr->{$php_flag_name} );
            $ref->{'default_name'}        = $php_flag_name;
            $ref->{'is_flag'}             = 1;
        }
        elsif ( exists $generic_hr->{$name} ) {
            $ref->{'trinary_admin_value'} = 0;
            $ref->{'value'}               = _get_value( $generic_hr->{$name} );
            $ref->{'default_name'}        = $name;
        }
        else {
            next;
        }

        $defaults_hr->{$name} = $ref;
    }

    return $defaults_hr;
}

=head2 _config_system_defaults_normalizer

Return a normalized config for the system_pool_defaults.yaml

There are no parameters.

See _normalize_config for full definition of normalized form.

=cut

sub _config_system_defaults_normalizer {
    my $system_pool_fname = $Cpanel::PHPFPM::Constants::system_yaml_dir . "/" . $Cpanel::PHPFPM::Constants::system_pool_defaults_yaml;
    if ( -e $system_pool_fname ) {
        my $system_default_hr = Cpanel::PHPFPM::_parse_fpm_yaml($system_pool_fname);
        return _config_generic_normalizer($system_default_hr);
    }

    return {};
}

=head2 _config_pool_normalizer

Return a normalized config for a users fpm yaml file.

Parameters:

$user - the user name

$domain - the domain to get config from

See _normalize_config for full definition of normalized form.

=cut

sub _config_pool_normalizer {
    my ( $user, $domain ) = @_;

    my $domain_fname = "$Cpanel::Config::userdata::Constants::USERDATA_DIR/${user}/${domain}.php-fpm.yaml";
    if ( -e $domain_fname ) {
        my $domain_hr = Cpanel::PHPFPM::_parse_fpm_yaml($domain_fname);
        return _config_generic_normalizer($domain_hr);
    }

    return {};
}

=head2 _config_combine_normalized

Combine 2 normalized FPM configs.  Where any item in the 2nd config takes precedence over
what is in the 1st confg.

Parameters:

$config_a - First normalized config

$config_b - Second normalized config

See _normalize_config for full definition of normalized form.

=cut

sub _config_combine_normalized {
    my ( $config_a, $config_b ) = @_;

    my $output_hr = {};

    # create a union of keys between config_a and config_b
    my %keys_lookup = map { $_ => 1 } ( keys %{$config_a}, keys %{$config_b} );
    my @keys        = sort keys %keys_lookup;

    foreach my $name (@keys) {
        my $from_a;
        my $from_b;

        if ( exists $config_a->{$name} ) {
            $from_a = $config_a->{$name};
        }

        if ( exists $config_b->{$name} ) {
            $from_b = $config_b->{$name};
        }

        if ( $from_a && !$from_b ) {
            $output_hr->{$name} = $from_a;
            next;
        }

        if ( $from_b && !$from_a ) {
            $output_hr->{$name} = $from_b;
            next;
        }

        # b supercedes a

        $output_hr->{$name} = $from_b;
    }

    return $output_hr;
}

=head2 _normalize_config

Take an array ref of config parameters and "normalize" them.

Normalization is of the form:

{
    "item_a" => {
        "base_flag_name" => "item_a",
        "value" => 22,
        "trinary_admin_value" => 0,
    },
    "item_b" => {
        "base_flag_name" => "item_b",
        "value" => 23,
        "trinary_admin_value" => 1,
    },
}

That is, it is a hash ref where the keys are the base names which points to a hashref
of the base name config item.

Parameters:

$config_ar - Array ref of config items

Returns a normalized hashref of the config items.

=cut

sub _normalize_config {
    my ($config_ar) = @_;
    my $output_hr = {};

    foreach my $ref ( @{$config_ar} ) {
        $output_hr->{ $ref->{'base_flag_name'} } = $ref;
    }

    return $output_hr;
}

=head2 _denormalize_config

Takes a normalized FPM config and formats it as a non normalized config.

[
    {
        "base_flag_name" => "item_a",
        "value" => 22,
        "trinary_admin_value" => 0,
    },
    {
        "base_flag_name" => "item_b",
        "value" => 23,
        "trinary_admin_value" => 1,
    },
]

That is, it returns an array ref of config items.

Parameters:

$config_ar - Array ref of config items

=cut

sub _denormalize_config {
    my ($config_hr) = @_;
    my $output_ar = [];

    foreach my $key ( keys %{$config_hr} ) {
        my $ref = $config_hr->{$key};

        delete $ref->{'is_flag'}      if exists $ref->{'is_flag'};
        delete $ref->{'default_name'} if exists $ref->{'default_name'};

        push( @{$output_ar}, $ref );
    }

    return $output_ar;
}

our $localdomains_hr;

=head2 _is_valid_local_domain

It first validates if the domain name is valid as a domain name.  It then
validates if the domain is local to this server.

Parameters:

$domain - a domain name to validate.

Returns 1 if this is a valid local domain.

Returns 0 otherwise.

=cut

sub _is_valid_local_domain {
    my ($domain) = @_;

    return 1 if ( $domain eq "" );

    # make sure the domain is valid as a domain name
    return 0 if ( !Cpanel::Validate::Domain::valid_wild_domainname($domain) );

    # is it a valid local domain
    if ( !$localdomains_hr ) {
        $localdomains_hr = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    }

    return 1 if exists $localdomains_hr->{$domain};
    return 0;
}

=head2 _get_domains_pool_config

Get a domain's FPM pool config.

Parameters:

$domain - a local domain name.

Returns a normalized hashref of the domains pool config.

=cut

sub _get_domains_pool_config {
    my ($domain) = @_;

    return if ( !_is_valid_local_domain($domain) );

    require Cpanel::AcctUtils::DomainOwner::Tiny;
    my $user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);

    my $user_parms_hr = _config_pool_normalizer( $user, $domain );

    return $user_parms_hr;
}

=head2 config_get

This is part of the WHM xml_api.   It gets either a domains
pool config, or the system defaults.  The list of returned
values are limited to the values we currently edit via
the UI (encoded in @_config_parms).

The args will contain "domain" to get the config.
If the domain is present and blank or not present the
system defaults are returned.

Returns args and metadata as an api call.

Also returns a config array ref.

$args->{'config'} = [
    {
        "base_flag_name" => "pm_max_children",
        "value" => 12,
        "trinary_admin_value" => 0
    },
    {
        "base_flag_name" => "pm_max_requests",
        "value" => 13,
        "trinary_admin_value" => 0
    },
];

=cut

sub config_get {
    my ( $args, $metadata ) = @_;

    $locale //= Cpanel::Locale->get_handle();

    my $domain = "";
    $domain = $args->{'domain'} if ( exists $args->{'domain'} );

    my $cpanel_defaults      = _config_cpanel_defaults_normalizer();
    my $system_pool_defaults = _config_system_defaults_normalizer();

    my $combined_values_hr = {};

    $combined_values_hr = _config_combine_normalized( $cpanel_defaults, $system_pool_defaults );

    if ( $domain ne "" ) {
        if ( !_is_valid_local_domain($domain) ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $locale->maketext('This server does not host this domain. Enter a domain on this server.');

            return {};
        }

        my $user_parms_hr = _get_domains_pool_config($domain);
        $combined_values_hr = _config_combine_normalized( $combined_values_hr, $user_parms_hr );
    }

    # deal with values set to blank, the get portion should be blank and
    # not ""

    foreach my $base_flag_name ( keys %{$combined_values_hr} ) {
        if ( $combined_values_hr->{$base_flag_name}->{'value'} eq '""' ) {
            $combined_values_hr->{$base_flag_name}->{'value'} = '';
        }
    }

    if ( exists $combined_values_hr->{'doc_root'}->{'value'} ) {
        my $value = $combined_values_hr->{'doc_root'}->{'value'};
        my $len   = length($value);
        my $idx   = index( $value, '"' );
        my $ridx  = rindex( $value, '"' );

        if ( $len > 0 && $idx >= 0 && ( $ridx == $len - 1 ) ) {
            $value = substr( $value, 1, $ridx - 1 );
            $combined_values_hr->{'doc_root'}->{'value'} = $value;
        }
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    my $config_ar = _denormalize_config($combined_values_hr);

    my $output_hr = {
        'domain' => $domain,
        'config' => $config_ar,
    };

    return $output_hr;
}

our %_valid_config_keys = (
    'trinary_admin_value' => 1,
    'base_flag_name'      => 1,
    'value'               => 1,
);

=head2 _validate_config

Validate that the config array that was passed into config_set
is of the form that we expect.  This intended to prevent various
shenanigans.

Parameters:

The config array passed into config_set.

Returns 1 if the config is valid.
Returns 0 otherwise.

=cut

sub _validate_config {
    my ($config_ar) = @_;

    my $count = 0;
    foreach my $config_item ( @{$config_ar} ) {

        # invalid keys?
        foreach my $key ( keys %{$config_item} ) {
            if ( !exists $_valid_config_keys{$key} ) {
                return 0;
            }
        }

        # are all keys present?
        foreach my $key ( keys %_valid_config_keys ) {
            return 0 if !exists $config_item->{$key};
        }
    }

    return 1;
}

sub _fix_doc_root {
    my ($combined_values_hr) = @_;

    if ( exists $combined_values_hr->{'doc_root'}->{'value'} ) {
        my $value = $combined_values_hr->{'doc_root'}->{'value'};
        if ( $value !~ m/^".*"$/ ) {

            # always surround value with double quotes to deal with a dir with
            # spaces in them
            $combined_values_hr->{'doc_root'}->{'value'} = "\"$value\"";
        }
    }

    return;
}

=head2 config_set

This is part of the WHM xml_api.   You would pass in the
config for either a domain or for the system defaults.

Args will contain the following values:

$args->{'domain'} - the domain name to set these config
parameters to.  If domain is blank or not present set the
system defaults.

$args->{'validate_only'} - If this is set to 1, just validate
the config and return, but do not set the config.  If it is
set to zero or not present, the config will be validated
and set.

And the config to set.

$args->{'config'} = [
    {
        "base_flag_name" => "pm_max_children",
        "value" => 12,
        "trinary_admin_value" => 0
    },
    {
        "base_flag_name" => "pm_max_requests",
        "value" => 13,
        "trinary_admin_value" => 0
    },
];

=cut

sub config_set {
    my ( $args, $metadata ) = @_;

    $locale //= Cpanel::Locale->get_handle();

    my $domain = "";
    $domain = $args->{'domain'} if ( exists $args->{'domain'} );
    $args->{'validate_only'} //= 0;

    if ( !exists $args->{'config'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('The parameter [asis,config] has no values. Enter a value for the [asis,config] parameter and try again.');

        return {};
    }

    # the config has a hard definition, lets validate it.
    my $config_ar = $args->{'config'};
    if ( !_validate_config($config_ar) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $locale->maketext('One or more of the configuration parameters is incorrect. Check the parameters and try again.');

        return {};
    }

    if ( $domain ne "" ) {
        my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_domains( [$domain] );
        if ( $php_config_ref->{$domain}->{'phpversion_or_inherit'} eq 'inherit' ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $locale->maketext('You cannot configure [asis,PHP-FPM] parameters when the domain’s [asis,PHP] Version is set to “[asis,inherit]”.');

            return {};
        }
    }

    # look for some known issues that could be a problem
    foreach my $record ( @{ $args->{'config'} } ) {
        if ( $record->{'value'} eq '' ) {
            $record->{'value'} = '""';
        }
    }

    my $input_config    = _normalize_config($config_ar);
    my $cpanel_defaults = _config_cpanel_defaults_normalizer();

    my $combined_values_hr = $cpanel_defaults;

    if ( $domain ne "" ) {
        if ( !_is_valid_local_domain($domain) ) {
            $metadata->{'result'} = 0;
            $metadata->{'reason'} = $locale->maketext('This server does not host this domain. Enter a domain on this server.');

            return {};
        }

        my $system_pool_defaults = _config_system_defaults_normalizer();
        my $user_parms_hr        = _get_domains_pool_config($domain);
        $combined_values_hr = _config_combine_normalized( $cpanel_defaults,    $system_pool_defaults );
        $combined_values_hr = _config_combine_normalized( $combined_values_hr, $user_parms_hr );
        $combined_values_hr = _config_combine_normalized( $combined_values_hr, $input_config );
    }
    else {
        my $system_pool_defaults = _config_system_defaults_normalizer();
        $combined_values_hr = _config_combine_normalized( $cpanel_defaults,    $system_pool_defaults );
        $combined_values_hr = _config_combine_normalized( $combined_values_hr, $input_config );
    }

    _fix_doc_root($combined_values_hr);

    my $denormalized_config = _denormalize_config($combined_values_hr);

    my $actual_fname;
    if ( $domain eq "" ) {
        $actual_fname = $Cpanel::PHPFPM::Constants::system_yaml_dir . "/" . $Cpanel::PHPFPM::Constants::system_pool_defaults_yaml;
    }
    else {
        require Cpanel::AcctUtils::DomainOwner::Tiny;

        my $user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);
        $actual_fname = "$Cpanel::Config::userdata::Constants::USERDATA_DIR/${user}/${domain}.php-fpm.yaml";
    }

    my $existing_yaml_hr = {};

    if ( -e $actual_fname ) {
        $existing_yaml_hr = Cpanel::PHPFPM::_parse_fpm_yaml($actual_fname);
        my %lookup;
        foreach my $parm (@_config_parms) {
            $lookup{$parm} = 1;
        }

        # strip out the parameters that we are editing.
        # so that it only contains values that are custom to the file
        my @keys = keys %{$existing_yaml_hr};
        foreach my $name (@keys) {
            delete $existing_yaml_hr->{$name} if exists $lookup{$name};
            my $base_flag_name;
            if ( $name =~ m/php_value_(.+)$/ ) {
                $base_flag_name = $1;
            }
            elsif ( $name =~ m/php_flag_(.+)$/ ) {
                $base_flag_name = $1;
            }
            elsif ( $name =~ m/php_admin_value_(.+)$/ ) {
                $base_flag_name = $1;
            }
            elsif ( $name =~ m/php_admin_flag_(.+)$/ ) {
                $base_flag_name = $1;
            }

            # keep value, if this not a php_ item, as it is not in our
            # config_parms
            next if !defined $base_flag_name;

            if ( exists $lookup{$base_flag_name} ) {
                delete $existing_yaml_hr->{$name};
            }
        }
    }

    require Cpanel::TempFile;

    my $temp_obj              = Cpanel::TempFile->new();
    my $tempdir               = $temp_obj->dir();
    my $temp_yaml_config_file = $tempdir . '/myconfig.yaml';

    my $results_ref;

    $results_ref = generate_temp_yaml_config( $temp_yaml_config_file, $denormalized_config, $existing_yaml_hr );
    if ( $results_ref->{'Status'} == 0 ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $results_ref->{'Message'};

        return {};
    }

    $results_ref = evaluate_pool_config( $domain, $temp_yaml_config_file );
    if ( $results_ref->{'Status'} != 1 ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = $results_ref->{'Error'};

        return {};
    }

    # if we are here we have passed validation

    if ( $args->{'validate_only'} ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'OK';

        return {};
    }

    if ( $domain eq "" ) {
        require Cpanel::FileUtils::Copy;
        require Cpanel::ServerTasks;

        Cpanel::FileUtils::Copy::safecopy( $temp_yaml_config_file, $actual_fname );

        # rebuild all
        Cpanel::ServerTasks::schedule_task( ['PHPFPMTasks'], $Cpanel::PHPFPM::Constants::delay_for_rebuild, 'rebuild_fpm' );
        Cpanel::ServerTasks::schedule_task( ['PHPFPMTasks'], 240,                                           'ensure_fpm_on_boot' );
    }
    else {
        require Cpanel::FileUtils::Copy;
        require Cpanel::PHPFPM::RebuildQueue::Adder;
        require Cpanel::ServerTasks;

        Cpanel::FileUtils::Copy::safecopy( $temp_yaml_config_file, $actual_fname );

        # rebuild this users fpm
        Cpanel::PHPFPM::RebuildQueue::Adder->add($domain);
        Cpanel::ServerTasks::schedule_task( ['PHPFPMTasks'], $Cpanel::PHPFPM::Constants::delay_for_rebuild, 'rebuild_fpm' );
        Cpanel::ServerTasks::schedule_task( ['PHPFPMTasks'], 240,                                           'ensure_fpm_on_boot' );
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return {};
}

1;
