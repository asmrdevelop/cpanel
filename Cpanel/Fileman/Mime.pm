package Cpanel::Fileman::Mime;

# cpanel - Cpanel/Fileman/Mime.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#use warnings;

our $VERSION = '1.0';

#-------------------------------------------------------------------------------------------------
# Purpose:  This module contains the mime specific functionality shared between Cpanel::Fileman
# and Cpanel::API::Fileman.
#-------------------------------------------------------------------------------------------------
# Developer Notes:
#-------------------------------------------------------------------------------------------------
# TODO:
#-------------------------------------------------------------------------------------------------

# Cpanel Dependencies
use Cpanel       ();
use Cpanel::Mime ();

use Cwd ();

# Caches
my %MEMORIZED_SIZES;
my %MIME_IMAGES;
my %SPECIAL_FILES;
my $MIME_TYPES;
my %PACKAGE_EXTENSIONS = ( zip => 1, gz => 1, bz2 => 1, tar => 1, rar => 1, tgz => 1 );

# Cache state
my $loaded_mimename_data;
my $loaded_mimetypes_map;

#-------------------------------------------------------------------------------------------------
# Name:
#   load_mimename_data
# Desc:
#   Loads the expensive mime data structures only once...
# Arguments:
#   N/A
# Returns:
#   N/A
#-------------------------------------------------------------------------------------------------
sub load_mimename_data {
    %SPECIAL_FILES = (
        "$Cpanel::homedir"             => 'homeb',
        "$Cpanel::homedir/mail"        => 'mail',
        "$Cpanel::homedir/www"         => 'publichtml',
        "$Cpanel::homedir/public_html" => 'publichtml',
        "$Cpanel::homedir/public_ftp"  => 'publicftp',
    );

    # Load the mime images files to get the correlations
    my $theme = _get_current_theme();
    if ( opendir( my $mime_icon_dir, "/usr/local/cpanel/base/frontend/$theme/mimeicons" ) ) {
        %MIME_IMAGES = map { ( $_ =~ /(.*)\.png$/ )[0] => undef } grep { /\.png$/ } readdir($mime_icon_dir);
        closedir($mime_icon_dir);
    }
    $loaded_mimename_data = 1;
    return 1;
}

#-------------------------------------------------------------------------------------------------
# Name:
#   get_mime_type_map
# Desc:
#   Retrieves a list of all the mime-types and their extension mappings for this system.
# Arguments:
#   force - bool - if true, force reloads the mime type data
# Returns:
#   hash reference - to mime information.
#-------------------------------------------------------------------------------------------------
sub get_mime_type_map {
    my ($force) = @_;

    if ( !$loaded_mimetypes_map || $force ) {
        my %sys_and_user_mime = ( Cpanel::Mime::system_mime(), Cpanel::Mime::user_mime() );

        #          'application/octet-stream' => 'bin dms lha lzh exe class so dll dmg iso',
        my $mimetype;
        $MIME_TYPES = {
            map {
                $mimetype = $_;
                map { ( $_ =~ /\.?(.+)$/ )[0] => $mimetype } split( /\s+/, $sys_and_user_mime{$mimetype} )
            } keys %sys_and_user_mime
        };

        $loaded_mimetypes_map = 1;
    }

    return $MIME_TYPES;
}

#-------------------------------------------------------------------------------------------------
# Name:
#   get_mime_type
# Desc:
#   Looks up the mime-type information for a given file.
# Arguments:
#   dir - string - path to the file.
#   file - string - file name.
#   filetype - string - type of the file.
#   rMIMEINFO - hash ref - table of mime-type information.
#   in_stat_cache - bool - true if its in the stat cache, false otherwise.
#   force - bool - if true, force reloads the mime type data
# Returns:
#   string - cpanel mime type
#   string - cpanel mime name
#   string - actual mime type
#   string - actual mime name
#-------------------------------------------------------------------------------------------------
sub get_mime_type {
    my ( $dir, $file, $filetype, $rMIMEINFO, $in_stat_cache, $force ) = @_;

    my ( $mimename, $mimetype, $raw_mime_name, $raw_mime_type );

    $dir =~ s{/+\z}{};

    my $path  = "$dir/$file";
    my $dpath = Cwd::abs_path($path);

    # Fix the file type if this is a symbolic link.
    $filetype = "dir" if $path ne $dpath && -d $dpath;

    load_mimename_data() if !$loaded_mimename_data || $force;

    if ( !defined $filetype || $filetype ne 'dir' ) {
        my $ext = ( split( /\./, $dpath ) )[-1];
        if ( $ext eq 'cgi' ) {
            my $file_is_valid_cgi = $in_stat_cache ? ( -z _ || -T _ ) : ( -z $dpath || -T _ );
            $mimename = $mimetype = ( $file_is_valid_cgi ? 'text/cgi' : $rMIMEINFO->{$ext} );
        }
        else {
            $raw_mime_name = $raw_mime_type = $mimename = $mimetype = $rMIMEINFO->{$ext};
        }

        if ($mimetype) {
            $mimename      =~ tr{/}{-};
            $raw_mime_name =~ tr{/}{-};
            return ( $mimetype, $mimename, $raw_mime_type, $raw_mime_name ) if exists $MIME_IMAGES{$mimename};
        }

        my $start_of_mime_type = '';
        if ( exists $PACKAGE_EXTENSIONS{$ext} ) {
            $start_of_mime_type = 'package';
        }
        elsif ($mimetype) {
            if ( $mimetype =~ m{/(?:tar|zip|gzip|bzip)} ) {
                $start_of_mime_type = 'package';
            }
            else {
                $mimetype =~ m{\A([^/]+)};
                $start_of_mime_type = $1 || q{};
            }
        }

        if ( !exists $MIME_IMAGES{"$start_of_mime_type-x-generic"} ) {
            $start_of_mime_type = 'text';
        }

        if ( !$raw_mime_type ) {

            # This happens for tar, zip, gzip, bzip as well as other unidentified file types.
            ( $raw_mime_type, $raw_mime_name ) = ( "$start_of_mime_type/x-generic", "$start_of_mime_type-x-generic" );
        }

        return ( "$start_of_mime_type/x-generic", "$start_of_mime_type-x-generic", $raw_mime_type, $raw_mime_name );
    }
    else {
        if ( defined $SPECIAL_FILES{$dpath} && exists $MIME_IMAGES{ $SPECIAL_FILES{$dpath} } ) {
            return ( $SPECIAL_FILES{$dpath}, $SPECIAL_FILES{$dpath}, 'httpd/unix-directory', 'httpd-unix-directory' );
        }
        return ( 'httpd/unix-directory', 'httpd-unix-directory', 'httpd/unix-directory', 'httpd-unix-directory' );
    }
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _get_current_theme
# Desc:
#   Gets the current theme for the user.
# Arguments:
#   N/A
# Returns:
#   string - theme for the current user.
#-------------------------------------------------------------------------------------------------
sub _get_current_theme {
    return $Cpanel::CPDATA{'RS'};
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _get_special_files
# Desc:
#   Gets the list of special files. (Mainly for tests)
# Arguments:
#   N/A
# Returns:
#   hash ref - hash of the special files mappings.
#-------------------------------------------------------------------------------------------------
sub _get_special_files {
    return \%SPECIAL_FILES;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _get_mime_images
# Desc:
#   Gets the list of mime images loaded for the current theme. (Mainly for tests)
# Arguments:
#   N/A
# Returns:
#   hash ref - hash of the special files mappings.
#-------------------------------------------------------------------------------------------------
sub _get_mime_images {
    return \%MIME_IMAGES;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _get_loaded
# Desc:
#   Checks if the caches have been loaded. (Mainly for tests)
# Arguments:
#   N/A
# Returns:
#   bool - 1 if loaded, undef otherwise.
#-------------------------------------------------------------------------------------------------
sub _get_loaded {
    return $loaded_mimename_data;
}

1;
