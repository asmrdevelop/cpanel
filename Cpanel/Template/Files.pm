package Cpanel::Template::Files;

# cpanel - Cpanel/Template/Files.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Debug ();

our ( $tmpl_dir, $tmpl_source_dir ) = ( '/var/cpanel/templates', '/usr/local/cpanel/src/templates' );

sub get_service_template_file {
    my ( $service, $skip_local, $name ) = @_;

    return if !$service;

    $skip_local ||= 0;
    $name       ||= 'main';

    # Check for local version of main template file
    my $template_file =
        -e $tmpl_dir . '/' . $service . '/' . $name . '.local' && !$skip_local ? $tmpl_dir . '/' . $service . '/' . $name . '.local'
      : -e $tmpl_dir . '/' . $service . '/' . $name . '.default'               ? $tmpl_dir . '/' . $service . '/' . $name . '.default'
      : -e $tmpl_source_dir . '/' . $service . '/' . $name . '.default'        ? $tmpl_source_dir . '/' . $service . '/' . $name . '.default'
      :                                                                          '';

    if ( !$template_file ) {
        return wantarray ? ( 0, "Template file for $service not located" ) : 0;
    }
    Cpanel::Debug::log_info("'local' template in use ($template_file)") if $template_file =~ m{local$};
    return $template_file;
}

sub get_branding_template_file {
    my ( $service, $opts ) = @_;
    return if !$service;

    # TODO: per reseller branding of template files
    my $branding_dir = '/usr/local/cpanel/whostmgr/docroot/themes/' . $opts->{'branding'} . '/branding/default/' . $service;
    if ( -e $branding_dir . '/' . $opts->{'template'} ) {
        return $branding_dir . '/' . $opts->{'template'};
    }
    elsif ( -e $tmpl_dir . '/' . $service . '/' . $opts->{'template'} ) {
        return $tmpl_dir . '/' . $service . '/' . $opts->{'template'};
    }
    else {
        return $tmpl_source_dir . '/' . $service . '/' . $opts->{'template'};
    }
}

1;
