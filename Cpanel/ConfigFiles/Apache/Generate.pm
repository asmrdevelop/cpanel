package Cpanel::ConfigFiles::Apache::Generate;

# cpanel - Cpanel/ConfigFiles/Apache/Generate.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

######################################################################################################
#### This module is a modified version of EA3’s distiller’s code, it will be cleaned up via ZC-5317 ##
######################################################################################################

use strict;
use warnings;

use Cpanel::Debug          ();
use Cpanel::WildcardDomain ();

sub generate_config_file {
    my $opts_hr = shift;
    my $local   = $opts_hr->{local} || 0;

    require Cpanel::Template;
    require Cpanel::Transaction::File::Raw;
    require Cpanel::ConfigFiles::Apache::Config;

    my $input_hr = Cpanel::ConfigFiles::Apache::Config::get_config_with_all_vhosts( local => $local );

    # Allow versioned template files
    my $versioned_service =
      exists $input_hr->{_use_target_version} && $input_hr->{_use_target_version} ne ''
      ? "apache" . $input_hr->{_use_target_version}
      : "apache";

    # For use in the configuration templates which use the wildcard_safe and legacy_wildcard_safe functions
    # Verified correct. -JNK 1.18.03
    $input_hr->{wildcard_safe}        = \&Cpanel::WildcardDomain::encode_wildcard_domain;
    $input_hr->{legacy_wildcard_safe} = \&Cpanel::WildcardDomain::encode_legacy_wildcard_domain;

    # Process template file
    my $skip_local = $local ? 0 : 1;
    my ( $status, $output_ref ) = Cpanel::Template::process_template( $versioned_service, $input_hr, { skip_local => $skip_local } );
    if ( !$status ) {
        my $msg = "Could not process template for $versioned_service: $output_ref";
        Cpanel::Debug::log_warn($msg);
        return { status => 0, message => $msg };
    }
    elsif ( !exists $opts_hr->{path} ) {
        my $msg = "Configuration module for apache did not specify a valid target file path";
        Cpanel::Debug::log_warn($msg);
        return { status => 0, message => $msg };
    }

    my $config_perms =
        $input_hr->{_target_conf_perms} ? $input_hr->{_target_conf_perms}
      : -e $opts_hr->{path}             ? ( ( stat(_) )[2] & 0777 )
      :                                   0644;

    # Write new configuration file
    my $trans = Cpanel::Transaction::File::Raw->new( path => $opts_hr->{path}, permissions => $config_perms );
    $trans->set_data($output_ref);
    my ( $ok, $msg ) = $trans->save_and_close();
    if ( !$ok ) {
        my $message = "Unable to write $input_hr->{path} [$msg]: $!";
        Cpanel::Debug::log_warn($message);
        return { status => 0, message => $message };
    }

    return { status => 1, message => "Succeeded" };
}

1;
