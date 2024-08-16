package Cpanel::WebTemplates;

# cpanel - Cpanel/WebTemplates.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Template::Simple ();
use Cpanel::PwCache          ();

our %web_template_pages = (
    'default'   => '',
    'moving'    => '',
    'redirect'  => '',
    'suspended' => '',

);

sub process_web_template {
    my ( $template_name, $language, $owner, $dataref ) = @_;

    $dataref->{'template_file'} = fetch_template_path( $template_name, $language, $owner );
    $dataref->{'print'}         = 1;

    my ( $status, $output_ref ) = Cpanel::Template::Simple::process_template( 'webtemplates', $dataref );

    return ( $status, $output_ref );
}

sub fetch_template_path {
    my ( $template_name, $language, $owner, $opref ) = @_;
    if ( !$language ) {
        $language = 'english';
    }

    $template_name =~ s/\///g;
    $language      =~ s/\///g;
    $owner         =~ s/\///g;

    my $base_path = $language . '/' . $template_name . '.tmpl';

    my @PATHS = ( '/var/cpanel/webtemplates/' . $owner, '/var/cpanel/webtemplates' );

    if ( $opref->{'nonexistant'} ) {
        return $PATHS[0] . '/' . $base_path;
    }

    foreach my $path (@PATHS) {
        if ( -e $path . '/' . $base_path ) {
            return $path . '/' . $base_path;
        }
    }

    if ( !$opref->{'customonly'} && !$opref->{'nobackcompat'} ) {

        #backwards compat
        if ( $template_name eq 'suspended' ) {
            my $homedir = $owner eq 'root' ? apache_paths_facade->dir_docroot() : Cpanel::PwCache::gethomedir($owner);
            if ( -e $homedir . '/public_html/suspended.page/index.html' ) {
                return $homedir . '/public_html/suspended.page/index.html';
            }
        }
        elsif ( $template_name eq 'default' ) {
            my $homedir = apache_paths_facade->dir_docroot();
            if ( -e $homedir . '/index_original.html' ) {
                return $homedir . '/index_original.html';
            }
        }
    }

    if ( !$opref->{'customonly'} ) {
        @PATHS = ( '/usr/local/cpanel/etc/webtemplates/' . $owner, '/usr/local/cpanel/etc/webtemplates' );
    }

    foreach my $path (@PATHS) {
        if ( -e $path . '/' . $base_path ) {
            return $path . '/' . $base_path;
        }
    }
    return undef;
}

1;
