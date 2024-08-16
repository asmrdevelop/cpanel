
# cpanel - Whostmgr/ModSecurity.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity;

use strict;
use warnings;

use Carp ();

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Exception        ();
use Cpanel::FileUtils::Write ();
use Cpanel::LoadFile         ();
use Cpanel::Locale::Lazy 'lh';
use Cpanel::ModSecurity ();

*has_modsecurity_installed = *Cpanel::ModSecurity::has_modsecurity_installed;

my $httpd_bin;

=head1 NAME

Whostmgr::ModSecurity

=head1 DESCRIPTION

This module contains only helper functions and constants in support of the
mod_security configuration API.

=head1 SUBROUTINES

=head2 config_prefix()

Constant: The absolute path of the Apache configuration directory under which
mod_security config files are kept.

=cut

sub config_prefix {
    return apache_paths_facade->dir_conf();
}

=head2 stage_suffix()

Constant: The suffix to be applied to the staging copy of a mod_security
configuration file that has been updated but not yet deployed.

=cut

sub stage_suffix {
    return '.STAGE';
}

sub modsec_primary_conf {
    return 'modsec2.conf';
}

sub modsec_cpanel_conf {
    return 'modsec2.cpanel.conf';
}

sub modsec_user_conf {
    return 'modsec2.user.conf';
}

sub abs_modsec_cpanel_conf_datastore {
    return '/var/cpanel/modsec_cpanel_conf_datastore';
}

sub abs_modsec_cpanel_conf_template {

    # version-less so it can be owned by the connector to mod sec 3.0, 3.1, ad infinitum
    return '/var/cpanel/templates/apache2_4/modsec.cpanel.conf.tt' if -e '/var/cpanel/templates/apache2_4/modsec.cpanel.conf.tt';
    return '/usr/local/cpanel/shared/templates/modsec2.cpanel.conf.tmpl';
}

sub abs_secdatadir {
    return '/var/cpanel/secdatadir';
}

# Directives that we force to be present in modsec2.cpanel.conf (controlled by WHM, not by EasyApache),
# but which are not manageable by the administrator.
sub fixed_directives_ar {
    return [ [ 'SecDataDir', abs_secdatadir() ] ];
}

sub get_config_paths {
    my ($config)              = @_;
    my $abs_config_path       = get_safe_config_filename($config);
    my $abs_config_path_stage = $abs_config_path . Whostmgr::ModSecurity::stage_suffix();
    return ( $abs_config_path, $abs_config_path_stage );
}

sub to_relative {
    my ($path) = @_;
    return '' if !$path;
    my $config_prefix = config_prefix();
    $path =~ s{^\Q$config_prefix\E/}{}o;
    return $path;
}

=head2 get_safe_config_filename()

Turn an unsafe/untrusted relative filename into a safe absolute filename
under apache_paths_facade->dir_conf(). The return value must always
be a filename safe for opening, regardless of what input was supplied.

=cut

sub get_safe_config_filename {
    my ($config) = @_;

    if ( !length $config ) {
        Carp::croak lh()->maketext(q{The configuration name cannot be empty.});
    }

    my ($sanitized) = $config =~ m{\A([a-zA-Z0-9_\-./]{1,512})\z};
    if ($sanitized) {
        Carp::croak lh()->maketext(q{The configuration name cannot contain two consecutive periods.})  if $sanitized =~ /\.\./;
        Carp::croak lh()->maketext(q{The configuration name must contain the string “[asis,modsec]”.}) if $sanitized !~ /modsec/;
        Carp::croak lh()->maketext(q{The configuration name must end with the suffix “[asis,.conf]”.}) if $sanitized !~ /\.conf\z/;
        if (
            ( $sanitized eq 'modsec2.cpanel.conf' || $sanitized eq 'modsec2.user.conf' )
            && (   -e Whostmgr::ModSecurity::config_prefix() . '/modsec/modsec2.cpanel.conf'
                || -e Whostmgr::ModSecurity::config_prefix() . '/modsec/modsec2.cpanel.conf.PREVIOUS'
                || -e Whostmgr::ModSecurity::config_prefix() . '/modsec/modsec2.user.conf'
                || -e Whostmgr::ModSecurity::config_prefix() . '/modsec/modsec2.user.conf.PREVIOUS' )
        ) {
            return Whostmgr::ModSecurity::config_prefix() . '/modsec/' . $sanitized;
        }
        return Whostmgr::ModSecurity::config_prefix() . '/' . $sanitized;
    }
    Carp::croak lh()->maketext(q{The configuration name contains invalid characters.});
}

sub relative_modsec_user_conf {
    return to_relative( get_safe_config_filename( modsec_user_conf() ) );
}

=head2 actual_httpd_bin()

Returns the actual httpd binary if possible. Failing that, returns whatever matches httpd
under the PATH directories (which will be a wrapper script).

Using the actual binary is necessary for some operations (-c) because on 2.2 the wrapper fails
to accept all arguments the binary accepts.

=cut

sub actual_httpd_bin {
    $httpd_bin ||= apache_paths_facade->bin_httpd();
    return $httpd_bin;
}

=head2 vendor_configs_dir()

Constant: Returns the name of the directory containing vendor-supplied mod_security
configuration files (as opposed to user configs). This is I<just> the name of the directory,
not the full path to it.

=cut

sub vendor_configs_dir {
    return 'modsec_vendor_configs';
}

=head2 vendor_meta_prefix()

Constant: Returns the path to the directory containing mod_security vendor metadata.

=cut

sub vendor_meta_prefix {
    return '/var/cpanel/modsec_vendors';
}

sub abs_vendor_meta_urls {
    return ( vendor_meta_prefix() . '/installed_from.yaml' );
}

=head2 validate_rule()

=head3 Purpose

Validates a mod_security rule without actually adding it to any configuration file.
This may be used by UIs that want to provide "as-you-type" validation of an input
box, making it easier to experiment with rule syntax.

=head3 Arguments

  - The rule text to be validated.

=head3 Returns

  - If the rule is valid, this function returns a true value.

=head3 Throws

  - If the rule is invalid, this function throws a Cpanel::Exception::ModSecurity::InvalidRule
    containing the text of the error.

=head3 Limitations

  - The rule is validated as if it were being added directly to the end of the configuration
    as it stands at the moment the API function is called. Cumulative changes from queue files
    are not accounted for. For example, if there is already a queued add for a rule with id
    '12345', and you call validate_rule for another with the same id, this won't (currently)
    be detected.

=cut

sub validate_rule {
    my $rule = shift;

    # Write the rule to a temporary conf file, which we will try to include. This is more reliable
    # than trying to pass the rule itself as an argument after -c (case 141013).
    require Cpanel::TempFile;
    my $tf            = Cpanel::TempFile->new();
    my $dir           = $tf->dir();
    my $validate_conf = $dir . '/validate.conf';
    Cpanel::FileUtils::Write::write( $validate_conf, $rule );

    require Cpanel::SafeRun::Errors;
    my $output = Cpanel::SafeRun::Errors::saferunallerrors( actual_httpd_bin(), '-t', '-c', qq{Include "$validate_conf"} );
    return 1 if $output =~ m{^Syntax OK}m;
    die Cpanel::Exception::create( 'ModSecurity::InvalidRule', [ error => $output ] );
}

=head2 version()

Returns the version of mod security if it is installed. Otherwise returns false.

=cut

sub version {
    return Cpanel::LoadFile::load_if_exists($Cpanel::ModSecurity::MODSEC_VERSION_FILE) || '';
}

sub validate_httpd_config {
    my ($self) = @_;
    require Cpanel::SafeRun::Errors;
    my $output = Cpanel::SafeRun::Errors::saferunallerrors( Whostmgr::ModSecurity::actual_httpd_bin(), '-t' );
    if ($?) {
        die lh()->maketext( q{The system could not validate the new [asis,Apache] configuration because [asis,httpd] exited with a nonzero value. [asis,Apache] produced the following error: [_1]}, $output ) . "\n";
    }
    return 1;
}

sub extract_vendor_id_from_config_name {
    my ($config)    = @_;
    my ($vendor_id) = $config =~ m{^modsec_vendor_configs/([^/]+)/};
    return $vendor_id;
}

# These are configured to use the "local" range based on the ranges listed here
# https://github.com/andristeiner/modsecurity-rules/blob/master/modsecurity.conf
sub custom_rule_id_range_start { return 1 }
sub custom_rule_id_range_end   { return 99_999 }

sub abs_modsec_transaction_log { return '/var/cpanel/logs/modsec_transaction.log' }

1;
