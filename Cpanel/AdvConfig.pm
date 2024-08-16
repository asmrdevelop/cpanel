package Cpanel::AdvConfig;

# cpanel - Cpanel/AdvConfig.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Debug                        ();
use Cpanel::CachedDataStore              ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::LoadModule                   ();
use Cpanel::CPAN::Hash::Merge            ();
use Cpanel::WildcardDomain               ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::AdvConfig::Setup             ();

Cpanel::CPAN::Hash::Merge::set_behavior('RIGHT_PRECEDENT');

our $VERSION = '1.5';

#
#In list context, returns (1) or (0, $error).
#
#In scalar context, returns 1 (success) or 0 (failure).
#(Consider always checking for errors to facilitate support/debugging!)
#
sub generate_config_file {    ## no critic qw(ProhibitExcessComplexity)
    my $opts_ref   = shift;
    my $service    = $opts_ref->{'service'};    # required
    my $force      = $opts_ref->{'force'}      || 0;
    my $skip_local = $opts_ref->{'skip_local'} || 0;

    Cpanel::LoadModule::load_perl_module('Cpanel::Template');
    Cpanel::LoadModule::load_perl_module('Cpanel::Transaction::File::Raw');
    Cpanel::Validate::FilesystemNodeName::validate_or_die($service);

    # Validate input
    if ( !$service ) {
        my $msg = 'No service specified';
        Cpanel::Debug::log_warn($msg);
        return wantarray ? ( 0, $msg ) : 0;
    }

    my $module = "Cpanel::AdvConfig::$service";
    Cpanel::LoadModule::load_perl_module($module);

    # Fetch service config values
    my ( $needs_update, $input_hr );

    my $get_config_opts = { 'reload' => 1, 'skip_local' => $skip_local, opts => $opts_ref };

    my $conf_obj;

    if ( $module->can('new') ) {
        $conf_obj = $module->new();
        eval { ( $needs_update, $input_hr ) = $conf_obj->get_config($get_config_opts) };
    }
    else {
        eval { ( $needs_update, $input_hr ) = $module->can('get_config')->($get_config_opts) };
    }

    if ($@) {
        my $msg = "Failed to exec get_config in module Cpanel::AdvConfig::$service: $@";
        Cpanel::Debug::log_warn($msg);
        return wantarray ? ( 0, $msg ) : 0;
    }

    use strict 'refs';
    if ( !defined $needs_update || !ref $input_hr ) {
        my $error = ref $input_hr ? $! : $input_hr;
        my $msg   = "Failed to get $service configuration: $error";
        Cpanel::Debug::log_warn($msg);
        return wantarray ? ( 0, $msg ) : 0;
    }

    foreach my $key ( keys %{$opts_ref} ) {
        if ( exists $input_hr->{$key} ) {
            $input_hr->{$key} = $opts_ref->{$key};
        }
    }

    # Generate new configuration file if needed
    if ( $needs_update || $force ) {

        # Allow versioned template files
        my $versioned_service =
          exists $input_hr->{'_use_target_version'} && $input_hr->{'_use_target_version'} ne ''
          ? $service . $input_hr->{'_use_target_version'}
          : $service;

        # Update templates if possible and necessary
        if ($conf_obj) {
            $conf_obj->update_templates($versioned_service);
        }
        else {
            eval {
                if ( my $sub = "Cpanel::AdvConfig::${service}"->can('update_templates') ) { &$sub($versioned_service); }
            };
        }

        #This function is deprecated as of cPanel/WHM 11.25.1 and will eventually be removed.
        #Please replace it in any custom config templates with TT2's unique() array vmethod.
        $input_hr->{'uniq'} = sub {
            Cpanel::Debug::log_info("Call to deprecated uniq() function in $versioned_service template. Please replace this function call with Template Toolkit's built-in unique() array virtual method, e.g. change \"uniq( some_array )\" to \"some_array.unique()\".");
            my %tmp = map { $_ => 1 } @{ $_[0] };
            return keys %tmp;
        };

        # For use in the configuration templates which use the wildcard_safe and legacy_wildcard_safe functions
        # Verified correct. -JNK 1.18.03
        $input_hr->{'wildcard_safe'}        = \&Cpanel::WildcardDomain::encode_wildcard_domain;
        $input_hr->{'legacy_wildcard_safe'} = \&Cpanel::WildcardDomain::encode_legacy_wildcard_domain;

        # Process template file
        my ( $status, $output_ref ) = Cpanel::Template::process_template( $versioned_service, $input_hr, { 'skip_local' => $skip_local } );
        if ( !$status ) {
            my $msg = "Could not process template for $versioned_service: $output_ref";
            Cpanel::Debug::log_warn($msg);
            return wantarray ? ( 0, $msg ) : 0;
        }
        elsif ( !exists $input_hr->{'_target_conf_file'} ) {
            my $msg = "Configuration module for $service did not specify a valid target file path";
            Cpanel::Debug::log_warn($msg);
            return wantarray ? ( 0, $msg ) : 0;
        }

        my $config_perms =
            $input_hr->{'_target_conf_perms'}   ? $input_hr->{'_target_conf_perms'}
          : -e $input_hr->{'_target_conf_file'} ? ( ( stat(_) )[2] & 0777 )
          :                                       0644;

        # Write new configuration file
        my $trans = Cpanel::Transaction::File::Raw->new( 'path' => $input_hr->{'_target_conf_file'}, 'permissions' => $config_perms );
        $trans->set_data($output_ref);
        my ( $ok, $msg ) = $trans->save_and_close();
        if ( !$ok ) {
            my $message = "Unable to write $input_hr->{'_target_conf_file'} [$msg]: $!";
            Cpanel::Debug::log_warn($message);
            return wantarray ? ( 0, $message ) : 0;
        }

        # Force generation of any ancillary configuration files
        if ( $input_hr->{'_follow'} ) {
            return generate_config_file( $input_hr->{'_follow'}, 1 );
        }
        return wantarray ? ( 1, 'Succeeded' ) : 1;
    }
    else {
        return wantarray ? ( 1, 'Update not required' ) : 1;
    }
}

sub load_app_conf {
    my $service    = shift;
    my $skip_local = shift;
    my $conf_ref;
    if ( !$service ) {
        my $msg = 'No service specified';
        Cpanel::Debug::log_warn($msg);
        return wantarray ? ( 0, $msg ) : 0;
    }
    Cpanel::Validate::FilesystemNodeName::validate_or_die($service);
    if ( -e $Cpanel::AdvConfig::Setup::system_store_dir . '/' . $service . '/main' ) {

        # usage is safe as we own the file and dir
        $conf_ref = Cpanel::CachedDataStore::fetch_ref( $Cpanel::AdvConfig::Setup::system_store_dir . '/' . $service . '/main' );
    }
    if ( !$skip_local && -e $Cpanel::AdvConfig::Setup::system_store_dir . '/' . $service . '/local' ) {

        # Cpanel::Debug::log_info("'local' datastore in use ($Cpanel::AdvConfig::Setup::system_store_dir/$service/local)");

        # usage is safe as we own the file and dir
        my $local_conf_ref = Cpanel::CachedDataStore::fetch_ref( $Cpanel::AdvConfig::Setup::system_store_dir . '/' . $service . '/local' );
        %{$conf_ref} = %{ Cpanel::CPAN::Hash::Merge::merge( $conf_ref, $local_conf_ref ) };
    }
    return $conf_ref;
}

sub save_app_conf {
    my $service  = shift;
    my $to_local = shift;
    my $conf_hr  = shift;
    unless ($service) {
        my $msg = 'No service specified';
        Cpanel::Debug::log_warn($msg);
        return wantarray ? ( 0, $msg ) : 0;
    }
    unless ( $conf_hr && ref $conf_hr eq 'HASH' ) {
        my $msg = "Configuration hash not supplied for $service";
        Cpanel::Debug::log_warn($msg);
        return wantarray ? ( 0, $msg ) : 0;
    }

    Cpanel::AdvConfig::Setup::ensure_conf_dir_exists($service);

    my $validate_map;
    if ( $service !~ m/(ftpd$|cpsrvd$|cpdavd$)/ ) {

        # AdvConfig does not exist for FTP or cPanel Web and Dav services,
        my $module = "Cpanel::AdvConfig::$service";
        Cpanel::LoadModule::load_perl_module($module);
        {
            no strict 'refs';
            $validate_map = ${"$module\:\:validate_map"};
        }
    }

    foreach my $key ( keys %{$conf_hr} ) {
        my $value = $conf_hr->{$key};
        if ( $validate_map && exists $validate_map->{$key} && $value !~ m{$validate_map->{$key}} ) {
            my $msg = "The value “$value” for the key “$key” for the “$service” service is not valid.";
            return wantarray ? ( 0, $msg ) : 0;
        }
    }

    # usage is safe as we own the file and dir
    if ( Cpanel::CachedDataStore::store_ref( "$Cpanel::AdvConfig::Setup::system_store_dir/$service/" . ( $to_local ? 'local' : 'main' ), $conf_hr ) ) {
        return wantarray ? ( 1, "Stored configuration successfully for $service " ) : 1;
    }
    else {
        my $msg = "Failed to store configuration for ${service} : $!";
        Cpanel::Debug::log_warn($msg);
        return wantarray ? ( 0, $msg ) : 0;
    }
}

sub set_app_conf_key_value {
    my ( $service, $key, $value ) = @_;
    unless ($service) {
        my $msg = 'No service specified';
        Cpanel::Debug::log_warn($msg);
        return wantarray ? ( 0, $msg ) : 0;
    }
    unless ( length $key ) {
        my $msg = "Configuration key not supplied for $service";
        Cpanel::Debug::log_warn($msg);
        return wantarray ? ( 0, $msg ) : 0;
    }
    unless ( length $value ) {
        my $msg = "Configuration value not supplied for $service";
        Cpanel::Debug::log_warn($msg);
        return wantarray ? ( 0, $msg ) : 0;
    }

    Cpanel::Validate::FilesystemNodeName::validate_or_die($service);
    my $module = "Cpanel::AdvConfig::$service";
    Cpanel::LoadModule::load_perl_module($module);
    Cpanel::SafeDir::MK::safemkdir( $Cpanel::AdvConfig::Setup::system_store_dir . '/' . $service, '0700' );
    my $conf_file = $Cpanel::AdvConfig::Setup::system_store_dir . '/' . $service . '/main';
    my $validate_map;
    {
        no strict 'refs';
        $validate_map = ${"$module\:\:validate_map"};
    }

    if ( $validate_map && exists $validate_map->{$key} && $value !~ m{$validate_map->{$key}} ) {
        my $msg = "The value “$value” for the key “$key” for the “$service” service is not valid";
        return wantarray ? ( 0, $msg ) : 0;
    }

    my $conf_obj = Cpanel::CachedDataStore::loaddatastore( $conf_file, 1 );    # lock and load
    if ( 'HASH' ne ref $conf_obj->{'data'} ) {
        $conf_obj->{'data'} = {};
    }

    $conf_obj->{'data'}{$key} = $value;
    $conf_obj->save();

    if ( my $coderef = $module->can('process_config_changes') ) {
        $coderef->( $conf_obj->{'data'} );
    }

    return generate_config_file( { 'service' => $service } );
}

1;
