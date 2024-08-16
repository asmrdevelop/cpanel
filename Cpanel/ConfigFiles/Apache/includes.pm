package Cpanel::ConfigFiles::Apache::includes;

# cpanel - Cpanel/ConfigFiles/Apache/includes.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

######################################################################################################
#### This module is a modified version of EA3’s distiller’s code, it will be cleaned up via ZC-5317 ##
######################################################################################################

use strict;
use warnings;
use Cpanel::Logger        ();
use Cpanel::Encoder::Tiny ();
use Cpanel::Encoder::URI  ();
use Cpanel::LoadFile      ();
use Cpanel::SafeDir::MK   ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::ConfigFiles::Apache::modules ();

our %files = (
    'pre_main_global.conf' => {
        'active'  => 0,
        'content' => '',
        'version' => 'global',
    },
    'pre_virtualhost_global.conf' => {
        'active'  => 0,
        'content' => '',
        'version' => 'global',
    },
    'post_virtualhost_global.conf' => {
        'active'  => 0,
        'content' => '',
        'version' => 'global',
    },

    'pre_main_1.conf' => {
        'active'  => 0,
        'content' => '',
        'version' => '1',
    },
    'pre_virtualhost_1.conf' => {
        'active'  => 0,
        'content' => '',
        'version' => '1',
    },
    'post_virtualhost_1.conf' => {
        'active'  => 0,
        'content' => '',
        'version' => '1',
    },

    'pre_main_2.conf' => {
        'active'  => 0,
        'content' => '',
        'version' => '2',
    },
    'pre_virtualhost_2.conf' => {
        'active'  => 0,
        'content' => '',
        'version' => '2',
    },
    'post_virtualhost_2.conf' => {
        'active'  => 0,
        'content' => '',
        'version' => '2',
    },
);

our @default_error_codes = ( 400 .. 417, 422 .. 424, 500 .. 507, 510 );

sub init {
    my %options = @_;
    my $logger  = Cpanel::Logger->new();

    my $options_support = Cpanel::ConfigFiles::Apache::modules::get_options_support();
    if ( !$options_support->{'version'} ) {
        $logger->warn('Failed to fetch Apache version, defaulting to Apache 1');
        $options_support->{'version'} = 1;
    }
    my $target_version = substr( $options_support->{'version'}, 0, 1 );

    my $dir = apache_paths_facade->dir_conf_includes();

    if ( !-e $dir ) {
        Cpanel::SafeDir::MK::safemkdir($dir);
    }
    if ( !-d $dir ) {
        $logger->warn("Apache includes directory $dir does not exist");
        return;
    }

    my $errordocument_conf        = $dir . '/errordocument.conf';
    my $create_errordocument_conf = 0;

    if ( -e $errordocument_conf ) {
        if ( open my $et_fh, '<', $errordocument_conf ) {
            while ( my $line = readline($et_fh) ) {
                next if $line =~ m/^\s*#/;
                if ( $line =~ m/\.shtml\s*#/ ) {    # Check for EOL comments as these will not work with Apache 2.x
                    $logger->info("Detected EOL comments in $errordocument_conf. Rebuilding.");
                    $create_errordocument_conf = 1;
                    last;
                }
            }
            close $et_fh;
        }
        else {
            $logger->warn("Failed to open $errordocument_conf: $!");
            $create_errordocument_conf = 1;
        }
    }
    else {
        $create_errordocument_conf = 1;
    }

    if ($create_errordocument_conf) {
        eval { require HTTP::Status };
        my $has_status = exists $INC{'HTTP/Status.pm'} ? 1 : 0;
        if ( open my $ed_fh, '>', $errordocument_conf ) {
            foreach my $error_code (@default_error_codes) {
                my $error_type = '# ' . $error_code;
                if ($has_status) {
                    $error_type .= ' - ' . HTTP::Status::status_message($error_code);
                }
                print {$ed_fh} "$error_type\n";
                print {$ed_fh} "ErrorDocument $error_code /$error_code.shtml\n\n";
            }
            close $ed_fh;
        }
        else {
            $logger->warn("Could not open '$errordocument_conf' for writing: $!");
        }
    }

    foreach my $file ( keys %files ) {
        my $file_vers = substr( $file, -6, 1 );
        $files{$file}{'active'} = ( $target_version eq $file_vers || $file_vers eq 'l' ) ? 1 : 0;
        if ( !$options{'encode'} || $options{'encode'} eq 'none' ) {
            $files{$file}{'content'} = Cpanel::LoadFile::loadfile( $dir . '/' . $file );
        }
        elsif ( $options{'encode'} eq 'uri' ) {
            $files{$file}{'content'} = Cpanel::Encoder::URI::uri_encode_str( Cpanel::LoadFile::loadfile( $dir . '/' . $file ) );
        }
        elsif ( $options{'encode'} eq 'html' ) {
            $files{$file}{'content'} = Cpanel::Encoder::Tiny::safe_html_encode_str( Cpanel::LoadFile::loadfile( $dir . '/' . $file ) );
        }
        else {
            $files{$file}{'content'} = Cpanel::Encoder::Tiny::angle_bracket_encode( Cpanel::LoadFile::loadfile( $dir . '/' . $file ) );
        }
    }
    return;
}

1;
