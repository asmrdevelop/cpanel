package Cpanel::API::Fileman;

# cpanel - Cpanel/API/Fileman.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#use warnings;

our $VERSION = '1.0';

#-------------------------------------------------------------------------------------------------
# Purpose:  This module contains the API calls and support code related to file management
# operation.
#-------------------------------------------------------------------------------------------------
# Developer Notes:
#   1) Most of these API calls were ported from ULC/Cpanel/Fileman.pm.
#   2) Phoenix took the liberty to clean up the code layout and call syntax to be more
#   understandable.
#   3) Many of the ported functions only took parameters from form variables. We added support
#   for passing these parameters directly to the methods as well, but continue to support the
#   automatic retrieval from FORM or COOKIE as the original API did.
#   4) Many of the original private methods and module variables were duplicated here. This is a
#   temporary condition until the remainder of the API2 calls are changed to wrapper calls to this
#   library.
#-------------------------------------------------------------------------------------------------
# TODO:
#   1) Port the remaining relevant API 2 calls to this module.
#   2) Change the API 2 calls to call this module.
#   3) Add ability to filter by multiple mime-types to list_files.  Get all images?
#-------------------------------------------------------------------------------------------------

# Cpanel Dependencies
use Cpanel                             ();
use Cpanel::ClamScan                   ();
use Cpanel::ElFinder::Encoder          ();
use Cpanel::Encoder::Tiny              ();
use Cpanel::Encoding                   ();
use Cpanel::Fcntl::Constants           ();
use Cpanel::Fileman::HtmlDocumentTools ();
use Cpanel::Fileman::Mime              ();
use Cpanel::Fileman::Reserved          ();
use Cpanel::Fileman::Trash             ();
use Cpanel::FileUtils::Write           ();
use Cpanel::Locale                     ();
use Cpanel::Logger                     ();
use Cpanel::Math                       ();
use Cpanel::PwCache                    ();
use Cpanel::Quota                      ();
use Cpanel::SafeDir                    ();
use Cpanel::SafeDir::MK                ();
use Cpanel::SafeFile                   ();
use Cpanel::StringFunc::Trim           ();
use Cpanel::LoadModule                 ();

# Library Dependencies
use Cwd ();

my $allow_demo = { allow_demo => 1 };

our %API = (
    _needs_role          => 'FileStorage',
    _needs_feature       => "filemanager",
    transcode            => $allow_demo,
    list_files           => $allow_demo,
    get_file_information => $allow_demo,
    autocompletedir      => $allow_demo,
);

# Sanity check to prevent denial of service when processing large buffers.
# was set to 131070 to match Cpanel/Fileman.pm, which was not being enforced
# changing to 1MB to match limit enforced in filemanager.js
my $MAX_SAFE_BUFFER_SIZE = 1048576;

# Defaults
my $SHOW_HIDDEN_DEFAULT                = 0;
my $SHOW_PARENT_DEFAULT                = 0;
my $CHECK_FOR_LEAF_DIRECTORIES_DEFAULT = 0;
my $INCLUDE_MIME_TYPES_DEFAULT         = 0;
my $INCLUDE_PERMISSIONS_DEFAULT        = 0;
my $INCLUDE_GROUP_DEFAULT              = 0;
my $INCLUDE_USER_DEFAULT               = 0;
my $INCLUDE_HASH_DEFAULT               = 0;
my $LIMIT_TO_LIST_DEFAULT              = 0;
my $USE_STAT_RULES_DEFAULT             = 0;

# Constants
our %FILE_TYPES = (
    $Cpanel::Fcntl::Constants::S_IFREG  => 'file',
    $Cpanel::Fcntl::Constants::S_IFDIR  => 'dir',
    $Cpanel::Fcntl::Constants::S_IFCHR  => 'char',
    $Cpanel::Fcntl::Constants::S_IFBLK  => 'block',
    $Cpanel::Fcntl::Constants::S_IFIFO  => 'fifo',
    $Cpanel::Fcntl::Constants::S_IFLNK  => 'link',
    $Cpanel::Fcntl::Constants::S_IFSOCK => 'socket',
);

our @_RESERVED = @Cpanel::Fileman::Reserved::_RESERVED;

# Globals
my $logger;
my $locale;

# Caches
my %MEMORIZED_SIZES;
my $MIME_TYPES;

#-------------------------------------------------------------------------------------------------
# Name:
#   empty_trash
# Desc:
#   Does what it says on the tin
# Arguments:
#   $older_than - optional positive integer. Files older than $older_time days will be deleted.
# Returns:
#   Nothing.
# Exceptions:
#   Invalid arguments generate InvalidParameter exceptions.
#-------------------------------------------------------------------------------------------------
sub empty_trash {
    my ( $args, $result ) = @_;
    my ($older_than) = $args->get('older_than');

    Cpanel::Fileman::Trash::empty_trash($older_than);

    return 1;
}

#-------------------------------------------------------------------------------------------------
# Name:
#   get_file_content
# Desc:
#   Retrieve the content from the file
# Arguments:
#   $dir          - string -
#   $file         - string - path to the file to edit
#   $from_charset - string - if _DETECT_ tells the code to attempt to auto detect the file encoding, otherwise is should be a predefined encoding on the system.
#   $to_charset   - string - usually utf-8, transform the document in from_charset to this one. If set to _LOCALE_, the routine will lookup the char-set
#   from the current locale.
# Returns:
#   hash -
#       from_charset - Original character set
#       to_charset   - Transformed character set
#       dir          - Directory to look in for the file
#       filename     - File in the directory
#       path         - Full path to the file (synthetic - same as dir/filename)
#       content      - Content in the file in UTF-8 encoding
#
#-------------------------------------------------------------------------------------------------
sub get_file_content {

    my ( $args, $result ) = @_;
    my ( $dir, $file, $from_charset, $to_charset, $update_html_document_encoding ) = $args->get( 'dir', 'file', 'from_charset', 'to_charset', 'update_html_document_encoding' );

    $update_html_document_encoding = 1 if !defined $update_html_document_encoding;

    require Cpanel::Validate::Boolean;
    Cpanel::Validate::Boolean::validate_or_die($update_html_document_encoding);

    my $method = "Filemanager::get_file_content =>";

    # Setups the globals
    _initialize();

    # Validate the required parameters
    if ( !$file ) {
        $result->error('The parameter ‘file’ is required.');
        return;
    }

    # Validate the parameter values
    if ( !_is_safe_file_name($file) ) {
        $result->error('The parameter ‘file’ contains invalid characters for a filename. Do not include ,/\<>; characters in a filename.');
        return;
    }

    # Sanitize the arguments
    my $safe_dir  = defined $dir  && $dir  ? Cpanel::SafeDir::safedir($dir) : Cpanel::SafeDir::safedir('');
    my $safe_file = defined $file && $file ? $file                          : '';
    my $safe_path = Cwd::abs_path("$safe_dir/$safe_file");
    $from_charset ||= "utf-8";
    $to_charset   ||= "utf-8";

    # See if the file encoding needs to be detected
    if ( $from_charset && uc $from_charset eq '_DETECT_' ) {
        $from_charset = Cpanel::Encoding::guess_file($safe_path);    # Uses the same engine that FF uses to detect encoding.
    }

    # Lookup the character set for the current locale if
    # $to_charset requests the _LOCALE_.
    if ( !$to_charset || $to_charset eq '_LOCALE_' ) {

        # TODO: Add test for this...
        $to_charset = $locale->encoding();
    }

    # Normalize:
    # iconv doesn't automatically recognize "usascii" and "us-ascii" as the same,
    # so we leave punctuation in.
    # We only are changing the case to lower for these.
    $from_charset = lc $from_charset;
    $to_charset   = lc $to_charset;

    # See if the file exists in the users folders
    if ( !length $safe_path || !-e $safe_path ) {
        my $safe_path_string = length $safe_path ? $safe_path : '';
        $logger->info("$method The file “$safe_path_string” does not exist for the account.");
        $result->error( "The file “[_1]” does not exist for the account.", $safe_path_string );
        return;
    }

    # Load the content from them file via the encoding converter
    my ( $ok, $content ) = _load_content_with_encoding( 'path' => $safe_path, 'from_charset' => $from_charset, 'to_charset' => $to_charset );
    if ( !$ok ) {
        $result->raw_error($content);
        return;
    }

    if ($update_html_document_encoding) {

        # Update the document to match the to charset
        $$content = Cpanel::Fileman::HtmlDocumentTools::update_html_document_encoding( $$content, $to_charset );
    }

    # Build the results.
    $result->data(
        {
            'from_charset' => $from_charset,
            'to_charset'   => $to_charset,
            'dir'          => $safe_dir,
            'filename'     => $safe_file,
            'path'         => $safe_path,
            'content'      => $content ? $$content : '',
        }
    );
    return 1;
}

#-------------------------------------------------------------------------------------------------
# Name:
#   save_file_content
# Desc:
#   Save a file to the server in the specified directory using the specified character-set.
# Arguments:
#   dir - string - direct to save too... defaults to the absolute home directory for the account
#   file - string - filename to save too...
#   from_charset - string - char encoding
#   to_charset - string - char encoding
#   content - string - utf-8 encoded characters
#   fallback - bool - if true, will fall-back to saving in the current encoding, otherwise, will
#   filetype - string - cptt or empty
#   html - bool - if true, document will be treated as HTML; will attempt to update encoding in document header if document encoding has changed
#   just error out if there is an iconv error.
# Returns:
#   path  - string - actual path saved to.
#   from_charset - string - source character set (Normally uft8 coming from the UI)
#   to_charset - string - character set the content was saved to. If this is different then the
#   passed in to_charset it indicates that a fall-back occurred.
#-------------------------------------------------------------------------------------------------
sub save_file_content {

    my ( $args, $result ) = @_;
    my ( $dir, $file, $content, $to_charset, $from_charset, $fallback, $filetype, $html ) = $args->get( 'dir', 'file', 'content', 'to_charset', 'from_charset', 'fallback', 'filetype', 'html' );

    my $method = "Filemanager::save_file_content =>";

    # Setups the globals
    _initialize();

    # Validate the required parameters
    if ( !$file ) {
        $result->error('The parameter ‘file’ is required.');
        return;
    }

    # Validate the parameter values
    if ( !_is_safe_file_name($file) ) {
        $result->error('The parameter ‘file’ contains invalid characters for a filename. Do not include ,/\<>; characters in a filename.');
        return;
    }

    # Sanitize the arguments. Assumes utf-8 unless specified otherwise.
    $from_charset ||= 'utf-8';
    $to_charset   ||= 'utf-8';

    # Normalize:
    # iconv doesn't automatically recognize "usascii" and "us-ascii" as the same,
    # so we leave punctuation in.
    # We only are changing the case to lower for these.
    $from_charset = lc $from_charset;
    $to_charset   = lc $to_charset;

    # Sanitize the directory, file name and path generated from them.
    my $safe_dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : Cpanel::SafeDir::safedir('');
    my $safe_file = $file;
    my $safe_path = Cwd::abs_path("$safe_dir/$safe_file");

    # Support transitional cpautott files
    if ( $filetype && $filetype eq 'cpautott' && $safe_path =~ m{\.html$} ) {
        $safe_file =~ s{\.html$}{\.auto\.tmpl};
        symlink( $safe_file, $safe_path ) if !-e $safe_path;
        $safe_path =~ s{\.html$}{\.auto\.tmpl};
    }

    # Determine if we need to convert the encoding
    my $transcode = $from_charset ne $to_charset;

    my $ok;
    my $error;
    my $actual_charset;

    if ( !length $safe_path ) {
        $logger->info("$method The file “” does not exist for the account.");
        $result->error( "The file “[_1]” does not exist for the account.", '' );
        return;
    }

    # Get the permissions set for the new or updated file.
    # Usually we are saving things to the webroot so 0644 is a better idea
    my $perms = -e $safe_path ? ( ( stat($safe_path) )[2] & 07777 ) : 0644;

    if ($transcode) {

        if ($html) {

            # Update the document to match the to_charset encoding
            $content = Cpanel::Fileman::HtmlDocumentTools::update_html_document_encoding( $content, $to_charset );
        }

        # The caller requested an encoding conversion.
        ( $ok, $error, $actual_charset ) = _save_content_with_encoding(
            'path'         => $safe_path,
            'perms'        => $perms,
            'content'      => $content,
            'from_charset' => $from_charset,
            'to_charset'   => $to_charset,
            'fallback'     => $fallback
        );
    }
    else {
        $actual_charset = $to_charset;

        # Write the file as currently encoded from caller
        ( $ok, $error ) = _save_content(
            'path'    => $safe_path,
            'perms'   => $perms,
            'content' => $content,
        );
    }

    if ( !$ok ) {
        $result->raw_error($error);
        return;
    }
    else {
        # Update the quota since we just changed file content
        Cpanel::Quota::reset_cache();
        $result->data(
            {
                path         => $safe_path,
                from_charset => $from_charset,
                to_charset   => $actual_charset,
            }
        );
    }
    return 1;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _save_content
# Desc:
#   Save the content of the file to disk using it current encoding in memory, probably UTF8.
# Arguments:
#   $path    - string - path to write the file to.
#   $perms   - string - permission to write the file as
#   $content - string - content to write to the file
# Returns:
#   bool - true is succeeded, false otherwise
#   string - error message
#-------------------------------------------------------------------------------------------------
sub _save_content {

    my %args = @_;
    my ( $path, $perms, $content ) = ( @args{qw/path perms content/} );

    # Validate the required parameters
    if ( !$path ) {
        return ( 0, $locale->maketext('The parameter ‘path’ is required.') );
    }

    my $error;

    # Lock the target file
    my $lock = Cpanel::SafeFile::safelock($path);
    if ( !$lock ) {
        $error = $locale->maketext( 'Could not write “[_1]” since the file could not be locked: [_2]', $path, $! );
    }

    # Try to write the file
    if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( $path, $content, $perms ) ) {
        if ( $!{EBADF} ) {
            $error = $locale->maketext( 'Could not write “[_1]”, you may be over quota: [_2]', $path, $! );
        }
        else {
            $error = $locale->maketext( 'Could not write “[_1]”: [_2]', $path, $! );
        }
    }

    # Unlock the target file
    Cpanel::SafeFile::safeunlock($lock);

    return ( $error ? 0 : 1, $error );
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _save_content_with_encoding
# Desc:
#   Save a file to the server in the specified directory using the specified character-set.
# Arguments:
#   path          - string - absolute path to the files location on the file system.
#   perms         - string - permission to write the file as
#   content       - string - content to save to the file.
#   rom_charset   - string - char encoding
#   to_charset    - string - name of the char-set encoding for the saved file.
#   fallback      - bool   - if there is an error during content encoding, the system will
#   fall back to utf-8 storage if this flag is set, or will error out if this flag is not set.
# Returns:
#   ok               - bool   - true if succeeded, false otherwise.
#   error            - string - error message if an error occurred.
#   actual_charset   - string - name of the encoding actually used to save the file.
#-------------------------------------------------------------------------------------------------
sub _save_content_with_encoding {

    my %args = @_;
    my ( $path, $perms, $content, $from_charset, $to_charset, $fallback ) = ( @args{qw/path perms content from_charset to_charset fallback/} );

    my $method = "Filemanager::_save_content_with_encoding =>";

    # Validate the required parameters
    if ( !$path ) {
        return ( 0, $locale->maketext('The parameter ‘path’ is required.'), '' );
    }

    my $ok;
    my $error;
    my $actual_charset;

    if ( $from_charset eq $to_charset ) {

        # Same charset no transcode needed
        ( $ok, $error ) = _save_content(
            'path'    => $path,
            'perms'   => $perms,
            'content' => $content,
        );
        $actual_charset = $to_charset;
    }
    else {
        my $xcontent;

        # Attempt to transcode
        ( $ok, $xcontent ) = _transcode( 'content' => $content, 'from_charset' => $from_charset, 'to_charset' => $to_charset );
        if ( !$ok ) {

            # Save the error
            $error = $xcontent;

            # Since transcoding failed, see if the
            # caller wanted us to try saving it as UTF-8...
            if ($fallback) {

                # Write the content as is instead
                ( $ok, $error ) = _save_content(
                    'path'    => $path,
                    'perms'   => $perms,
                    'content' => $content,
                );
                $actual_charset = $from_charset || 'utf-8';
            }
            else {
                $logger->info("$method Could not transcode from $from_charset to $to_charset the following with '$error': $content.");

                # Just error out
                $error = $locale->maketext( 'Could not transcode the content from “[_1]” to “[_2]”: [_3]', $from_charset, $to_charset, $error );
            }
        }
        else {
            ( $ok, $error ) = _save_content(
                'path'    => $path,
                'perms'   => $perms,
                'content' => $xcontent,
            );
            $actual_charset = $to_charset;
        }
    }

    return ( $ok, $error, $actual_charset );
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _load_content
# Desc:
#   Load a files content into a buffer.
# Arguments:
#   path      - string - complete path to the file to process.
# Returns:
#   ok        - bool - true if successful, false otherwise.
#   content   - string - content of the file if succeeded, error message
#   otherwise.
#-------------------------------------------------------------------------------------------------
sub _load_content {

    # Get the arguments.
    my %args = @_;
    my ($path) = ( $args{'path'} );

    # Validate the required parameters
    if ( !$path ) {
        return ( 0, $locale->maketext('The parameter path is required.') );
    }

    my $content;
    my $error;

    if ( open my $read_fh, '<', $path ) {

        # We can access the file
        if ( -z $path ) {

            # Check to see if its empty
            $content = '';
        }
        else {
            # We just need to open the file and process it
            my $ok = read $read_fh, $content, $MAX_SAFE_BUFFER_SIZE;
            if ( !$ok ) {

                # Read failed
                $logger->info("Failed to read the file $path as $Cpanel::user: $!");
                $error = $locale->maketext( 'Could not read the file “[_1]” as “[_2]”: [_3]', $path, $Cpanel::user, $! );
            }

            if ( $ok && !eof($read_fh) ) {

                # File is to large, more the MAX_SAFE_BUFFER_SIZE
                $logger->info("The file $path for user $Cpanel::user is larger then the maximum allowed file size of $MAX_SAFE_BUFFER_SIZE.");
                $error = $locale->maketext( 'The file “[_1]” for user “[_2]” is larger then the maximum allowed file size of [format_bytes,_3].', $path, $Cpanel::user, $MAX_SAFE_BUFFER_SIZE );
            }
        }
        close $read_fh;
    }
    else {
        $error = $locale->maketext( 'Could not open “[_1]” as “[_2]”: [_3]', $path, $Cpanel::user, $! );
        $logger->warn("Could not open $path as $Cpanel::user: $!");
    }

    return ( 0, $error ) if $error;
    return ( 1, $content );
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _load_content_with_encoding
# Desc:
#   Load a file via the iconv program to convert the character set from the from_charset
#   to the to_charset.`
# Arguments:
#   $path          - string - complete path to the file to process.
#   $from_charset  - string - valid character set to convert the file from.
#   $to_charset    - string - valid character set to convert the file to.
# Returns:
#   $ok        - bool - true if successful, false otherwise.
#   $content   - string - content of the file after the conversion if succeeded, error message
#   otherwise.
#-------------------------------------------------------------------------------------------------
sub _load_content_with_encoding {

    # Get the arguments.
    my %args = @_;
    my ( $path, $from_charset, $to_charset ) = ( @args{qw/path from_charset to_charset/} );

    # Validate the required parameters
    if ( !$path ) {
        return ( 0, $locale->maketext('The parameter path is required.') );
    }
    if ( $to_charset && uc $to_charset eq "_DETECT_" ) { $to_charset = ""; }    #blank out the charset so it tries to detect

    my ( $content, $ok, $error );

    # Sanitize the input
    $from_charset ||= Cpanel::Encoding::guess_file($path);
    $to_charset   ||= Cpanel::Locale->get_handle()->encoding();                 # utf-8 probably

    # Normalize:
    # iconv doesn't automatically recognize "usascii" and "us-ascii" as the same,
    # so we leave punctuation in.
    # We only are changing the case to lower for these.
    $from_charset = lc $from_charset;
    $to_charset   = lc $to_charset;

    # Determine if we need ICONV?
    my $transcode = $from_charset ne $to_charset;

    # Change the data to be suitable for the browser, namely: make it utf-8
    if ($transcode) {

        # Load the content
        ( $ok, $content ) = _load_content( 'path' => $path );
        if ( !$ok ) {
            $error = $content;
        }
        else {
            # Convert the buffer charset
            ( $ok, $content ) = _transcode( 'content' => $content, 'from_charset' => $from_charset, 'to_charset' => $to_charset );
            if ( !$ok ) {
                $error = $content;
            }
        }
    }
    else {
        # no conversion needed, just load it normally
        ( $ok, $content ) = _load_content( 'path' => $path );
        if ( !$ok ) {
            $error = $content;
        }
    }

    return ( 0, $error ) if !$ok;
    return ( 1, length($content) ? \$content : () );
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _is_safe_file_name
# Desc:
#   Tests if the filename does not contain illegal characters.
# Arguments:
#   $file - string - filename to sanitize.
#   $allow_slash - bool - if true, will allow directory / otherwise it will reject directory /.
# Returns:
#   bool - true if file name is safe, false otherwise
#-------------------------------------------------------------------------------------------------
sub _is_safe_file_name {
    my ( $file, $allow_slash ) = @_;
    return 1 if !length $file;
    return   if ( $file                  =~ m/^(\.|\.\.)$/ );    # refuse . and ..
    return   if ( $file                  =~ tr/<>;// );          # refuse script special ones
    return   if ( !$allow_slash && $file =~ tr{/}{} );           # refuse slashes
    return 1;
}

#-------------------------------------------------------------------------------------------------
# Name:
#   transcode
# Desc:
#   Convert a buffer from one encoding to another.
# Args:
#    from_charset    - string - character set the data is already in. Defaults to utf-8.
#    to_charset      - string - character set the data should be trans-coded to.  Defaults to utf-8.
#    content         - string | string ref - content to convert from the from encoding to the to encoding.
#    discard_illegal - bool - if true, will discard characters that do not trans-code correctly.
#    If false, will keep the characters that do not trans-code correctly, but they will be the
#    default character that iconv uses in the given encoding for characters that are invalid
#    for that encoding.  Defaults to false.
#    transliterate   - bool - if true, will transliterate illegal characters to a legal character in
#    the to_char set based on the iconv rules for transliteration. if false, will just throw a
#    error.
#-------------------------------------------------------------------------------------------------
sub transcode {

    my ( $args, $result ) = @_;
    my ( $content, $from_charset, $to_charset, $discard_illegal, $transliterate ) = $args->get( 'content', 'from_charset', 'to_charset', 'discard_illegal', 'transliterate' );

    # Sanitize arguments
    # NOTE: We do not sanitize here since the _transcode method does this

    # Setups the globals
    _initialize();

    my ( $ok, $xfrm ) = _transcode( 'content' => $content, 'from_charset' => $from_charset, 'to_charset' => $to_charset, 'discard_illegal' => $discard_illegal, 'transliterate' => $transliterate );
    if ( !$ok ) {
        $result->raw_error($xfrm);
        return;
    }

    $result->data(
        {
            'charset' => $to_charset,
            'content' => $xfrm,         # CONSIDER: Should this return a refernce \$xfrm?
        }
    );
    return 1;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _transcode
# Desc:
#   Convert a buffer from one encoding to another.
# Args:
#   from_charset    - string - character set the data is already in. Defaults to UTF-8.
#   to_charset      - string - character set the data should be trans-coded to.  Defaults to UTF-8.
#   content         - string - content to write to the file.
#   discard_invalid - bool - if true, will discard characters that do not trans code correctly.
#   If false, will keep the characters that do not trans code correctly, but they will be the
#   default character that iconv uses in the given encoding for characters that are invalid
#   for that encoding.  Defaults to true.
# Return:
#   List
#       boolean - true if ok, false if failed.
#       string  - trans-coded string if successful, error message if failed.
#
#-------------------------------------------------------------------------------------------------
sub _transcode {
    my %CFG = @_;

    # Sanitize the arguments
    my $from_charset    = $CFG{'from_charset'}    || "utf-8";
    my $to_charset      = $CFG{'to_charset'}      || "utf-8";
    my $content         = $CFG{'content'}         || '';
    my $transliterate   = $CFG{'transliterate'}   || 0;
    my $discard_illegal = $CFG{'discard_illegal'} || 0;

    my ( $results, $error );

    if ( $from_charset eq $to_charset ) {

        # Leave the string alone
        $results = $content;
    }
    else {
        # Encode the string from native format to the alternative format

        #NOTE: Found this perl module. It really simplifies the code a lot.
        #CPAN:     https://metacpan.org/module/Text::Iconv
        #ICONV:    http://www.gnu.org/savannah-checkouts/gnu/libiconv/documentation/libiconv-1.13/iconv.3.html
        #ICONVCTL: http://www.gnu.org/savannah-checkouts/gnu/libiconv/documentation/libiconv-1.13/iconvctl.3.html
        Cpanel::LoadModule::load_perl_module('Text::Iconv');
        'Text::Iconv'->raise_error(1);
        if ( $discard_illegal && $to_charset !~ m/\/\/IGNORE/ ) {
            $to_charset = $to_charset . ( $discard_illegal ? '//IGNORE' : '' );
        }

        if ( $transliterate && $to_charset !~ m/\/\/TRANSLIT/ ) {
            $to_charset = $to_charset . ( $transliterate ? '//TRANSLIT' : '' );
        }

        my $converter = 'Text::Iconv'->new( $from_charset, $to_charset );

        local $@;

        eval {
            # NEED to have libiconv to make these work, but we don't right
            # now. This would be preferable to the above since.
            #eval { $converter->set_attr("transliterate", $transliterate) }; # disable transliteration
            #eval { $converter->set_attr("discard_ilseq", $discard_illegal) }; # do not discard illegal sequences
            $results = $converter->convert($content);
        };

        if ($@) {

            # If the destination charset set lacks a codepoint to
            # represent a character from the source charset, rather than
            # percolating a warning to the user, silently allow the user
            # to edit the file under the incompatible encoding anyway.
            # Please note that in Text::Iconv's Iconv.xs source, this
            # error is explicitly hardcoded and is not localized, so this
            # is a safe test.
            if ( $@ =~ /^Character not from source char set:/ ) {
                $results = $content;
            }
            else {
                warn;
                $error = $@;
            }
        }
    }

    return ( 0, $error ) if $error;
    return ( 1, $results );
}

#-------------------------------------------------------------------------------------------------
# Name:
#   upload_files
# Desc:
#   Processes the files that Cpanel::Form::parseform has already saved as
#   temporary files in ~/tmp and renames them. Optionally runs API2 getdiskinfo()
#   afterward.
# Arguments:
#   dir - string - directory to upload the files too. If not provided, looks in the
#   $Cpanel::FORM{'dir'}. If not provided, falls back to the users home folder.
#   files - hash - collection of file names as uploaded by the HTML FORM processor.  Hash keys
#   for files in this hash should start with the prefix 'file-'.  The CPANEL FORM processor
#   uses this convention by default. All over keys are ignored.
#   overwrite - boolean - If true, will overwrite any  existing files that exist with a new
#    version. If false, will not overwrite existing files. If not provided, will look at the
#    FORM{'overwrite'}. If not provided there, will default to false.
#   permissions - string - digits that represent the desired file permissions for all the
#    uploads in the batch. Defaults to 0644. Supports 0xxx or xxx passed either of which is
#    interpreted as an octal number.
#   get_disk_info - bool - If true, will return the diskinfo with upload returned data. If false
#   will not retrieve the new disk information. Defaults to false.
# Returns:
#   hash -
#       diskinfo - hash of the following:
#           file_upload_max_bytes - number - maximum number of byte for an upload
#           file_upload_must_leave_bytes - number - ???
#           file_upload_remain - number -
#           filesremain - number - files remaining
#           fileslimit - number - files limit
#           filesused - number - files used
#           spaceremain - number - disk space remaining
#           spacelimit - number - disk space limit
#           spaceused - number - disk space used
#       uploads - array - Contains the array of upload results where each entry contains:
#           file - string - Original file name of the upload
#           size - number - Size of the file uploaded in bytes?
#           status - bool - True if the file was copied to the selected directory, false otherwise
#           reason - string - if status is false, the reason why
#           warnings - array of strings - minor issues that resulted from the upload failing to
#           have ownership or permissions set correctly.
#-------------------------------------------------------------------------------------------------
sub upload_files {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $args, $result ) = @_;
    my ( $dir, $files, $overwrite, $permissions, $get_disk_info ) = $args->get( 'dir', 'files', 'overwrite', 'permissions', 'get_disk_info' );

    # Setups the globals
    _initialize();

    # Values from Cpanel::IxHash hashes should be returned verbatim.
    local $Cpanel::IxHash::Modify = 'none';

    # Get the defaults if not provided
    $dir = defined $dir ? $dir : $Cpanel::FORM{'dir'};
    my %files = defined $files && ref $files ? %{$files} : %Cpanel::FORM;
    $overwrite     = defined $overwrite     ? $overwrite     : int( $Cpanel::FORM{'overwrite'} || 0 );
    $get_disk_info = defined $get_disk_info ? $get_disk_info : int( $Cpanel::FORM{'get_disk_info'} || 0 );
    $permissions   = defined $permissions   ? $permissions   : $Cpanel::FORM{'permissions'};
    if ( defined $permissions ) {
        if ( $permissions !~ m/^[0]?[0-7]{3}$/ ) {
            $result->error('The parameter ‘permissions’ must contain a valid file system permission.');
            return;
        }
        $permissions = oct $permissions;
    }
    else {
        $permissions = 0644;    #User RW, Group R, Everybody R
    }

    # Sanitize the arguments
    my $safe_dir = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : Cpanel::SafeDir::safedir('');

    # Create the directory in the users folder if its missing
    if ( !-e $safe_dir ) {
        my $ok = Cpanel::SafeDir::MK::safemkdir($safe_dir);
        if ( !$ok ) {
            $result->error( 'Failed to create the directory [_1].', $safe_dir );
            return;
        }
    }

    # Change to the specified directory
    my $ok = chdir $safe_dir;
    if ( !$ok ) {
        $result->error( 'Cannot change directories into [_1].', $safe_dir );
        return;
    }

    # Process all the uploaded files
    my @uploads;
    my ( $num_succeeded, $num_failed, $num_warned ) = ( 0, 0, 0 );

  FILE:
    foreach my $file ( sort keys %files ) {
        next FILE if !$file;
        next FILE if $file =~ m/^file-(.*)-key$/;    # Ignore file-?-keys from the FORM processor
        next FILE if $file !~ m/^file-(.*)/;         # Ignore everything else that is not a file

        my ( $error, @warnings, $temp_file_path );
        my ( $will_overwrite, $file_size );

        my $original_file_path = $1;
        my $original_file_name = _get_filename_from_path_os_agnostic($original_file_path);

        # This should be OK, make text is already outputting HTML encoded characters into JSON responses...
        # I have no idea how much stuff is already relying on this behavior.
        # If we do the encoding in the JS, we end up with doubly encoded characters.

        my $original_file_path_html = Cpanel::Encoder::Tiny::safe_html_encode_str($original_file_path);
        my $original_file_name_html = Cpanel::Encoder::Tiny::safe_html_encode_str($original_file_name);
        my $temp_file_path_html     = Cpanel::Encoder::Tiny::safe_html_encode_str($temp_file_path);

        # Validate the parameter values
        if ( !_is_safe_file_name($original_file_name) ) {
            $error = $locale->maketext( 'The filename “[_1]” contains invalid characters. Do not include the ,/[output,lt][output,gt]; characters in the filename.', $original_file_name_html );
            $num_failed++;
        }
        else {

            # Get the name of the temporary file where the
            # FORM processor placed the uploaded file.
            $temp_file_path = $files{$file};
            $temp_file_path =~ s{\n}{}g;    #????

            if ( !-e $temp_file_path ) {
                $error = $locale->maketext( "The file “[_1]” you tried to upload was not in the [asis,/tmp] directory.", $original_file_path_html );
                $num_failed++;
            }
            else {
                # Check if the uploaded file contains a virus
                my $has_virus = Cpanel::ClamScan::ClamScan_scan($temp_file_path);    # WHY doesn't this have a use block?  Causing some weird processing???
                if ( $has_virus && $has_virus ne 'OK' && ( $has_virus !~ m/access file/i && $has_virus !~ m/no such/i ) ) {

                    $logger->info("Virus detected in upload $temp_file_path by user $Cpanel::user ($original_file_name): $has_virus");

                    $error = $locale->maketext( 'The file you uploaded, [_1], contains a virus so the upload was canceled: [_2]', $original_file_path_html, $has_virus );
                    $num_failed++;
                }
                else {

                    # Sanitize the path
                    my $safe_full_path      = "$safe_dir/$original_file_name";                                # ??? IS THIS SAFE REALLY???
                    my $safe_full_path_html = Cpanel::Encoder::Tiny::safe_html_encode_str($safe_full_path);

                    $will_overwrite = -e $safe_full_path;

                    if ( $will_overwrite && !$overwrite ) {

                        # Can overwrite so just fail out for this item
                        $error = $locale->maketext( "The file “[_1]” you uploaded already exists.", $original_file_path_html );
                        $num_failed++;
                    }
                    else {
                        #rename() clobbers an existing file
                        $ok = rename $temp_file_path, $safe_full_path;
                        if ( !$ok ) {
                            $error = $locale->maketext( "Upload Canceled: could not copy the file “[_1]” to “[_2]” due to the following error: [_3]", $temp_file_path_html, $safe_full_path_html, $! );
                            $num_failed++;
                        }
                        elsif ( -e $safe_full_path ) {
                            $file_size = ( stat(_) )[7];

                            # TODO: Seems invalid to chown, only root???
                            # Claim ownership of the file for the current user
                            $ok = chown( $<, $), $safe_full_path );
                            if ( !$ok ) {
                                push @warnings, $locale->maketext( "Could not change to ownership of the file “[_1]” from user “[_2]” to “[_3]” due to the following error: [_4]", $safe_full_path_html, $<, $), $! );
                                $logger->info("Change ownership of $safe_full_path from $< to $) failed: $!");
                            }

                            $ok = chmod( $permissions, $safe_full_path );
                            if ( !$ok ) {
                                push @warnings, $locale->maketext( "Could not change the file permissions of “[_1]” to “[_2]” due to the following error: [_3]", $safe_full_path_html, sprintf( '%04lo', $permissions ), $! );
                                $logger->info("Change permissions of $safe_full_path to $permissions failed: $!");
                            }

                            $num_succeeded++;
                        }
                    }
                }
            }
        }

        if ( $error || -e $temp_file_path ) {

            # Cleanup the temporary files
            if ( length $temp_file_path && -e $temp_file_path ) {
                $ok = unlink $temp_file_path;
                if ( !$ok ) {
                    push @warnings, $locale->maketext( 'Could not delete temporary file “[_1]”: [_2]', $temp_file_path_html, $! );
                    $logger->info("unlink $temp_file_path failed: $!");
                }
            }
        }

        my $reason;
        if ($error) {
            $reason = $error;
        }
        else {
            $reason =
                $will_overwrite
              ? $locale->maketext( "Upload of “[_1]” succeeded, overwrote existing file with your upload.", $original_file_name_html )
              : $locale->maketext( "Upload of “[_1]” succeeded.",                                           $original_file_name_html );
        }

        if ( scalar(@warnings) > 0 ) {
            $num_warned++;
        }

        push @uploads,
          {
            'file'     => $original_file_name,
            'size'     => $file_size,
            'status'   => !$error ? 1 : 0,
            'reason'   => $reason,
            'warnings' => \@warnings,
          };
    }

    Cpanel::Quota::reset_cache();    #since we just changed the quota usage

    # Build the results.
    my $data = {
        'uploads'   => \@uploads,
        'succeeded' => $num_succeeded,
        'warned'    => $num_warned,
        'failed'    => $num_failed,
    };

    if ($get_disk_info) {
        my $disk_info = Cpanel::Quota::getdiskinfo();
        $data->{'diskinfo'} = $disk_info;
    }

    # We want to return the data reguardless of the overall success or failure of the api.
    $result->data($data);

    # See if anything was uploaded, if not error out.
    if ( scalar(@uploads) == 0 ) {
        $result->error('You must specify at least one file to upload.');
        return 0;
    }
    elsif ( scalar(@uploads) == $num_failed ) {
        $result->error('Failed to upload any of the requested files with various failures.');
        return 0;
    }

    return 1;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _get_filename_from_path_os_agnostic
# Desc:
#   Gets the file name from a path.  Will work for DOS, WINDOWS, LINUX, UNIX and MAC paths
#   since we are allowing either / or \ separators.  Assumes that the last item in the path
#   is a file name.
# Args:
#   string - path to process.
# Return:
#   string - the file name.
#-------------------------------------------------------------------------------------------------
sub _get_filename_from_path_os_agnostic {
    my $path       = shift;
    my @path_parts = split( m{[\\/]}, $path );
    return $path_parts[-1];
}

#-------------------------------------------------------------------------------------------------
# Name:
#   list_files
# Desc:
#   Will return a sorted list of the directories and a sorted list of the files contained
#   in a giving directory.  Various options below allow you to change which fields are
#   present and some limited filters. For more extensive filtering use the standard API
#   filtering.
# Arguments:
#  args:
#   dir - string - directory to list files from.
#   types - string - optional | separated list of file types. If not provided all file types will
#   be returned. Limited to:
#       file - include files
#       dir - include directories
#       char - include char
#       block - include block
#       fifo - include fifo
#       link - include links
#       socket - include sockets
#   limit_to_list - bool - if true, will limit to the list passed in only_these_files or in the FORM
#       if only_these_files is not passed.  If looking in the FORM, will only select values for
#       elements with keys starting with filepath-.  If false or not provided, will list all the files
#       in the directory.
#   only_these_files - array string - array of files to check. If provided only the listed files will be
#       included in the listing. If not provided, the API will list all the files in the directory.
#   show_hidden - bool - hidden files start with the '.'. If this flag is true, hidden files will
#       be included in the listing. If false, the call will fall-back to the value in the showdotfiles
#       cookie, otherwise it will not show hidden files.  Defaults to false.
#   check_for_leaf_directories - bool - Since determining if a directory contains other directories
#       is expensive, this flag provides callers the ability to not check this condition. Pass a true
#       value to run the check and add the isleaf attribute to each item in the returned information,
#       or false to not run the check. Defaults to false.
#   mime_types   - string - optional | separated list of cpanel mapped mime types. If not provided, all mime types are
#       will be returned.  If included, this has the effect of setting include_mime to true as well, causing
#       the mime types to be loaded into the records.
#   raw_mime_types - string - optional | separated list of raw mime types. If not provided, all mime types are
#       will be returned.  If included, this has the effect of setting include_mime to true as well, causing
#       the mime types to be loaded into the records.
#   include_mime - bool - Since mime-types are expensive to calculate, this flag allows callers to
#       decide to load the mime type data in the results. Set to true to include the mime-type of the file
#       in the returned information and false to not add the mime-type to the returned information. Note:
#       if you include a filter or sort by mime-type, it will force this field to be calculated regardless
#       of this flag.
#   include_hash - bool - Since hashes are expensive to calculate, hash generation is disabled by default.
#       If true will generate a hash based on the file name and add it to the returned results.
#       If false, will not generate the hash or include it in the results.
#   include_permissions - bool - If true will parse out the owner read and write permission for the file or directory
#       and add it to the returned results. If false, will not parse or write these to the results.
#   include_group - bool - If true will provide the group name in the returned data.
#   include_user  - bool - If true will provide the user name in the returned data.
#   stat_rules - bool - if true, will loosen the safedir rules for the stats api2 call to allow dir to be the parent if there is
#   only one file requested an it is the users home folder.
#  results - object - used to return information to the api system.
# Returns:
#
#   An array info objects have the following fields:
#
#       fullpath  - string - full path to the file
#       path      - string - path only not include the file name or directory name
#       file      - string - file name or directory name
#       uid       - number - system user id of the owner of the file
#       gid       - number - system group id of the owner of the file.
#       size      - number - size of the file in bytes.
#       mtime     - timestamp - time the file was last modified
#       humansize - string - formated size of the file:  1K 1M 10M 45G
#       nicemode  - string - formatted file system mode.
#       mode      - number - mode from the stat of the file,
#       ctime     - timestamp - time the file was created
#       type      - string - type of the item (file, dir, char, block, fifo, link, socket)
#       absdir    - string - legacy field
#       mimetype  - string - Contains the mime type of the file. Only included if the include_mime
#           flag is true.
#       rawmimetype - string - Actual mime type of the file. Only included if the include_mime
#           flag is true.
#       isleaf    - bool - only provided in directory objects, true if the directory does not
#       have any sub-directories. False if it does contain one or more sub-directories.  Only
#           included if the check_leaf flag is true.
#       hash      - string - hash of the full path for the file or directory.  Only included if the
#           include_hash flag is  true.
#       phash     - string - hash of the parent path for the file or directory. Only included if the
#           include_hash flag is  true.
#       read      - bool - true if the file can be read, false otherwise. Only included if the
#           include_permissions flag is true.
#       write     - bool - true if the file can be written, false otherwise. Only included if the
#           include_permissions flag is true.
#       isparent  - bool - true if this is the parent record. not included otherwise. This field
#           is only present if the show_parent option is set.
#       user      - string - actual user name. Only provided if the include_user flag is set.
#       group     - string - actual group name. Only provided if the include_group flag is set.
#
#   If the show_parent flag is true, the first entry is the parent. If the parent is outside the
#   users folder, this entry is for the home directory for this user.
#-------------------------------------------------------------------------------------------------
sub list_files {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $args, $result )                                                     = @_;
    my ( $dir, $types, $limit_to_list, $stat_rules )                          = $args->get( 'dir', 'types', 'limit_to_list', 'stat_rules' );
    my ( $show_hidden, $check_for_leaf_directories )                          = $args->get( 'show_hidden', 'check_for_leaf_directories' );
    my ( $include_mime, $mime_types, $raw_mime_types )                        = $args->get( 'include_mime', 'mime_types', 'raw_mime_types' );
    my ( $include_hash, $include_permissions, $include_user, $include_group ) = $args->get( 'include_hash', 'include_permissions', 'include_user', 'include_group' );
    my ($show_parent) = $args->get('show_parent');
    my @only_these_files = ();

    # Constants

    # Setups the globals
    _initialize();

    # Make sure the home directory is initialize correctly in case it was
    # not setup or the owner removed a critical resource.
    _initialize_home_directory();

    # ??? WHY ???
    if ( length $dir && $dir eq '-1' ) {

        #special case for yui bugs
        $result->data( [] );
        return 1;
    }

    # Peeking at meta arguments to see if we need the specific columns
    my @filter_or_sort_keys           = grep { m/api\.(filter_column|sort_column)+d*/ } $args->keys();
    my $filter_or_sort_by_mimetype    = _has_filter_or_sort_key( $args, \@filter_or_sort_keys, [ 'mimetype', 'mimename' ] );
    my $filter_or_sort_by_hash        = _has_filter_or_sort_key( $args, \@filter_or_sort_keys, [ 'hash',     'phash' ] );
    my $filter_or_sort_by_permissions = _has_filter_or_sort_key( $args, \@filter_or_sort_keys, [ 'read',     'write' ] );
    my $filter_or_sort_by_user        = _has_filter_or_sort_key( $args, \@filter_or_sort_keys, ['user'] );
    my $filter_or_sort_by_group       = _has_filter_or_sort_key( $args, \@filter_or_sort_keys, ['group'] );

    # Get the defaults if not provided
    $show_hidden                = ( defined $show_hidden ? $show_hidden : _get_cookies()->{'showdotfiles'} ) || $SHOW_HIDDEN_DEFAULT;
    $show_parent                = defined $show_parent ? $show_parent : $SHOW_PARENT_DEFAULT;
    $include_mime               = $filter_or_sort_by_mimetype    || ( defined $mime_types && $mime_types ) || ( defined $raw_mime_types && $raw_mime_types ) || ( defined $include_mime ? $include_mime : $INCLUDE_MIME_TYPES_DEFAULT );
    $include_hash               = $filter_or_sort_by_hash        || ( defined $include_hash        ? $include_hash        : $INCLUDE_HASH_DEFAULT );
    $include_permissions        = $filter_or_sort_by_permissions || ( defined $include_permissions ? $include_permissions : $INCLUDE_PERMISSIONS_DEFAULT );
    $include_user               = $filter_or_sort_by_user        || ( defined $include_user        ? $include_user        : $INCLUDE_USER_DEFAULT );
    $include_group              = $filter_or_sort_by_group       || ( defined $include_group       ? $include_group       : $INCLUDE_GROUP_DEFAULT );
    $check_for_leaf_directories = defined $check_for_leaf_directories ? $check_for_leaf_directories : $CHECK_FOR_LEAF_DIRECTORIES_DEFAULT;
    $limit_to_list              = defined $limit_to_list              ? $limit_to_list              : $LIMIT_TO_LIST_DEFAULT;
    $types          ||= '';
    $mime_types     ||= '';
    $raw_mime_types ||= '';

    if ($limit_to_list) {
        @only_these_files = $args->exists("only_these_files") ? @{ $args->get("only_these_files") } : _get_files_from_form();
    }
    $stat_rules = defined $stat_rules ? $stat_rules : $USE_STAT_RULES_DEFAULT;

    # Sanitize the arguments
    my $safe_dir;
    if ( !$stat_rules ) {
        $safe_dir = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : Cpanel::SafeDir::safedir('');
    }
    else {
        # This case allows list_files to be used to
        # implement api2_statfiles for home folder.
        my (@HR)      = split( /\//, $Cpanel::abshomedir );
        my $user_home = pop(@HR);
        my $homes     = join( '/', @HR );
        if ( $dir eq $homes ) {
            @only_these_files = ($user_home);
            $safe_dir         = $homes;
        }
        else {
            $safe_dir = $dir ? Cpanel::SafeDir::safedir($dir) : Cpanel::SafeDir::safedir('');
        }
    }

    my @types_ar   = split( /\|/, $types );
    my $types_list = $types ? \@types_ar : undef;

    my @mime_types_ar   = split( /\|/, $mime_types );
    my $mime_types_list = $mime_types ? \@mime_types_ar : undef;

    my @raw_mime_types_ar   = split( /\|/, $raw_mime_types );
    my $raw_mime_types_list = $raw_mime_types ? \@raw_mime_types_ar : undef;

    # Validate the inputs
    if ( !-d $safe_dir ) {
        $result->error( 'The directory [_1] does not exist.', $safe_dir );
        return;
    }

    # If we are hashing, load the hash library
    my $parent_hash;
    if ($include_hash) {
        my ( $ok, $error ) = Cpanel::ElFinder::Encoder::initialize();
        if ( !$ok ) {
            $result->raw_error($error);
            return;
        }
        $parent_hash = Cpanel::ElFinder::Encoder::encode_path( $safe_dir, '_' );
    }

    my @FILES;
    if ($limit_to_list) {
        @FILES = sort { lc $a cmp lc $b } @only_these_files;
    }
    else {
        if ( opendir( my $dir_fh, $safe_dir ) ) {
            @FILES = sort { lc $a cmp lc $b } grep( !( $_ eq '.' || $_ eq '..' ), readdir($dir_fh) );
            closedir($dir_fh);
        }
    }

    if ( $include_mime && !$MIME_TYPES ) {
        $MIME_TYPES = Cpanel::Fileman::Mime::get_mime_type_map();
    }

    my ( @RSDDIRS, @RSDFILES, $safe_file );
    my ( $skip,    $FINFO,    $error );

    foreach my $file (@FILES) {

        # Validate the file passed in are safe
        if ( $limit_to_list && !_is_safe_file_name( $file, $stat_rules ) ) {
            $result->error( 'The file [_1] contains invalid characters for a filename. Do not include ,/\<>; characters in a filename.', $file );
        }
        else {
            $safe_file = $file;

            # Get the information for this file.
            ( $skip, $FINFO, $error ) = _package_file_information(
                'safe_file'                  => $safe_file,
                'safe_dir'                   => $safe_dir,
                'show_hidden'                => $show_hidden,
                'include_hash'               => $include_hash,
                'include_mime'               => $include_mime,
                'mime_types'                 => $mime_types_list,
                'raw_mime_types'             => $raw_mime_types_list,
                'include_permissions'        => $include_permissions,
                'include_group'              => $include_group,
                'include_user'               => $include_user,
                'check_for_leaf_directories' => $check_for_leaf_directories,
                'types'                      => $types_list,
                'parent_hash'                => $parent_hash
            );

            # Skip if it doesn't match the filters
            next if $skip;

            # Report an error if one occurred.
            $result->raw_error($error) if $error;

            # Put into correct list
            if ( $FINFO->{'type'} && $FINFO->{'type'} eq 'dir' ) {
                push( @RSDDIRS, $FINFO );
            }
            else {
                push( @RSDFILES, $FINFO );
            }
        }
    }

    # See if we want to include the parent folder information also.
    my $PARENT_INFO;
    if ($show_parent) {
        my $root = Cpanel::SafeDir::safedir('');
        if ( $root eq $safe_dir ) {
            $safe_file = '';
            if ( $include_hash && $parent_hash ) {
                $parent_hash = '';
            }
        }
        else {
            $safe_file = $safe_dir;
            my @parts = split( '/', $safe_dir );
            pop(@parts);
            $safe_dir = join( '/', @parts );
            $safe_dir = Cpanel::SafeDir::safedir($safe_dir);
            if ( $include_hash && $parent_hash ) {
                $parent_hash = Cpanel::ElFinder::Encoder::encode_path( $safe_dir, '_' );
            }
        }

        # Get the parent directory information for this file.
        ( $skip, $PARENT_INFO, $error ) = _package_file_information(
            'safe_file'                  => $safe_file,
            'safe_dir'                   => $safe_dir,
            'show_hidden'                => $show_hidden,
            'include_hash'               => $include_hash,
            'include_mime'               => $include_mime,
            'include_permissions'        => $include_permissions,
            'include_group'              => $include_group,
            'include_user'               => $include_user,
            'check_for_leaf_directories' => $check_for_leaf_directories,
            'parent_hash'                => $parent_hash
        );
        $result->raw_error($error) if $error;
        $PARENT_INFO->{'isparent'} = 1;
    }

    # Build the results.
    my @data = (
        @RSDDIRS,
        @RSDFILES,
    );

    if ($show_parent) {

        # Add the parent information record
        unshift @data, $PARENT_INFO;
    }

    $result->data( \@data );

    return 1;
}

#-------------------------------------------------------------------------------------------------
# Name:
#   get_file_information
# Desc:
#   Will return the same data structure as list_files for a single file or directory.  Various
#   options below allow you to change which fields are present.
# Arguments:
#   path - string - requested resource.
#   show_hidden - bool - hidden files start with the '.'. If this flag is true, hidden files will
#       be included in the listing. If false, the call will fall-back to the value in the showdotfiles
#       cookie, otherwise it will not show hidden files.  Defaults to false.
#   check_for_leaf_directories - bool - Since determining if a directory contains other directories
#       is expensive, this flag provides callers the ability to not check this condition. Pass a true
#       value to run the check and add the isleaf attribute to each item in the returned information,
#       or false to not run the check. Defaults to false.
#   include_mime - bool - Since mime-types are expensive to calculate, this flag allows callers to
#       decide to load the mime type data in the results. Set to true to include the mime-type of the file
#       in the returned information and false to not add the mime-type to the returned information. Note:
#       if you include a filter or sort by mime-type, it will force this field to be calculated regardless
#       of this flag.
#   include_hash - bool - Since hashes are expensive to calculate, hash generation is disabled by default.
#       If true will generate a hash based on the file name and add it to the returned results.
#       If false, will not generate the hash or include it in the results.
#   include_permissions - bool - If true will parse out the owner read and write permission for the file or directory
#       and add it to the returned results. If false, will not parse or write these to the results.
#   include_group - bool - If true will provide the group name in the returned data.
#   include_user  - bool - If true will provide the user name in the returned data.
# Returns:
#   The info object has the following fields:
#
#       fullpath  - string - full path to the file
#       path      - string - path only not include the file name or directory name
#       file      - string - file name or directory name
#       uid       - number - system user id of the owner of the file
#       gid       - number - system group id of the owner of the file.
#       size      - number - size of the file in bytes.
#       mtime     - timestamp - time the file was last modified
#       humansize - string - formated size of the file:  1K 1M 10M 45G
#       nicemode  - string - formatted file system mode.
#       mode      - number - mode from the stat of the file,
#       ctime     - timestamp - time the file was created
#       type      - string - type of the item (file, dir, char, block, fifo, link, socket)
#       absdir    - string - legacy field
#       mimetype  - string - Contains the mime type of the file. Only included if the include_mime
#           flag is true.
#       rawmimetype - string - Actual mime type of the file. Only included if the include_mime
#           flag is true.
#       isleaf    - bool - only provided in directory objects, true if the directory does not
#       have any sub-directories. False if it does contain one or more sub-directories.  Only
#           included if the check_leaf flag is true.
#       hash      - string - hash of the full path for the file or directory.  Only included if the
#           include_hash flag is  true.
#       phash     - string - hash of the parent path for the file or directory. Only included if the
#           include_hash flag is  true.
#       read      - bool - true if the file can be read, false otherwise. Only included if the
#           include_permissions flag is true.
#       write     - bool - true if the file can be written, false otherwise. Only included if the
#           include_permissions flag is true.
#       user      - string - actual user name. Only provided if the include_user flag is set.
#       group     - string - actual group name. Only provided if the include_group flag is set.
#-------------------------------------------------------------------------------------------------
sub get_file_information {
    my ( $args, $result ) = @_;
    my ($path) = $args->get('path');
    my ( $show_hidden, $check_for_leaf_directories )          = $args->get( 'show_hidden', 'check_for_leaf_directories' );
    my ( $include_mime, $include_hash, $include_permissions ) = $args->get( 'include_mime', 'include_hash', 'include_permissions' );
    my ( $include_user, $include_group )                      = $args->get( 'include_user', 'include_group' );

    # Constants

    # Setups the globals
    _initialize();

    # Make sure the home directory is initialize correctly in case it was
    # not setup or the owner removed a critical resource.
    _initialize_home_directory();

    my ( $dir, $file ) = _extract_directory_and_leaf_resource($path);

    # Validate the parameter values
    if ( !_is_safe_file_name($file) ) {
        $result->error('The path contains invalid characters for a file name. Do not include ,/\<>; characters in a file name part of the path.');
        return;
    }

    # Peeking at meta arguments to see if we need the specific columns
    my @filter_or_sort_keys           = grep { m/api\.(filter_column|sort_column)+d*/ } $args->keys();
    my $filter_or_sort_by_mimetype    = _has_filter_or_sort_key( $args, \@filter_or_sort_keys, [ 'mimetype', 'mimename' ] );
    my $filter_or_sort_by_hash        = _has_filter_or_sort_key( $args, \@filter_or_sort_keys, [ 'hash',     'phash' ] );
    my $filter_or_sort_by_permissions = _has_filter_or_sort_key( $args, \@filter_or_sort_keys, [ 'read',     'write' ] );
    my $filter_or_sort_by_user        = _has_filter_or_sort_key( $args, \@filter_or_sort_keys, ['user'] );
    my $filter_or_sort_by_group       = _has_filter_or_sort_key( $args, \@filter_or_sort_keys, ['group'] );

    # Get the defaults if not provided
    $show_hidden                = ( defined $show_hidden ? $show_hidden : ( _get_cookies()->{'showdotfiles'} || '' ) eq '1' ) || $SHOW_HIDDEN_DEFAULT;
    $include_mime               = $filter_or_sort_by_mimetype    || ( defined $include_mime        ? $include_mime        : $INCLUDE_MIME_TYPES_DEFAULT );
    $include_hash               = $filter_or_sort_by_hash        || ( defined $include_hash        ? $include_hash        : $INCLUDE_HASH_DEFAULT );
    $include_permissions        = $filter_or_sort_by_permissions || ( defined $include_permissions ? $include_permissions : $INCLUDE_PERMISSIONS_DEFAULT );
    $include_user               = ( defined $include_user  ? $include_user  : $INCLUDE_USER_DEFAULT );
    $include_group              = ( defined $include_group ? $include_group : $INCLUDE_GROUP_DEFAULT );
    $check_for_leaf_directories = defined $check_for_leaf_directories ? $check_for_leaf_directories : $CHECK_FOR_LEAF_DIRECTORIES_DEFAULT;

    # Sanitize the arguments
    my $safe_dir  = defined $dir && $dir ? Cpanel::SafeDir::safedir($dir) : Cpanel::SafeDir::safedir('');
    my $safe_file = $file;

    # Validate the inputs
    if ( !-d $safe_dir ) {
        $result->error( 'The directory [_1] does not exist.', $safe_dir );
        return;
    }

    # If we are hashing, load the hash library
    my $parent_hash;
    if ($include_hash) {
        my ( $ok, $error ) = Cpanel::ElFinder::Encoder::initialize();
        if ( !$ok ) {
            $result->raw_error($error);
            return;
        }
        $parent_hash = Cpanel::ElFinder::Encoder::encode_path($safe_dir);
    }

    if ( $include_mime && !$MIME_TYPES ) {
        $MIME_TYPES = Cpanel::Fileman::Mime::get_mime_type_map();
    }

    # Package up the file
    my ( $skip, $FINFO, $error ) = _package_file_information(
        'safe_file'                  => $safe_file,
        'safe_dir'                   => $safe_dir,
        'show_hidden'                => $show_hidden,
        'include_hash'               => $include_hash,
        'include_mime'               => $include_mime,
        'include_permissions'        => $include_permissions,
        'include_group'              => $include_group,
        'include_user'               => $include_user,
        'check_for_leaf_directories' => $check_for_leaf_directories,
        'parent_hash'                => $parent_hash
    );

    # Report an error if one occurred.
    if ($error) {
        $result->raw_error($error);
        return;
    }

    if ($skip) {
        $result->error( 'The file [_1] is not available.', $safe_file );
    }

    # Build the results.
    $result->data($FINFO);

    return 1;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   public
# Name:
#   autocompletedir
# Desc:
#   Given a directory name prefix, returns any directories and/or files that begin with that string.
# Arguments:
#   path     - The prefix of the paths to complete.
#   dirsonly - (Boolean) If true, only include directories in the reply.
#   list_all - (Boolean) List all directories and/or files underneath of the specified directory instead
#              of looking for partial name matches. If this option is specified, then the 'path' argument
#              must be the exact path of a directory and may not contain a partial filename.
#   html     - Whether the results should be encoded as HTML, defaults to yes.
# Returns:
#   An array of hashes, each of which contains:
#     file - A file or directory matching the provided pattern.
#-------------------------------------------------------------------------------------------------

sub autocompletedir {
    my ( $args, $result ) = @_;

    my $path         = $args->get('path');
    my @PATH         = split( /\//, $path );
    my $isroot       = $path =~ /\/$/;
    my $matchname    = '';
    my $list_all     = $args->get('list_all');
    my $dirsonly     = $args->get('dirsonly');
    my $skipreserved = $args->get('skipreserved');
    my $html         = $args->get('html');

    $html = 1 unless defined $html;

    # Testing a root folder, preserving legacy behavior
    if ( !$list_all || !$isroot ) {
        $matchname = pop(@PATH);
    }

    my $dir     = Cpanel::SafeDir::safedir( join( '/', @PATH ) );
    my $homedir = Cpanel::SafeDir::safedir();
    my $basedir = substr( $dir, length($homedir) );
    my $dh;
    my @matches;
    opendir( $dh, $dir );

    my %reserved = map { $_ => 1 } @_RESERVED;
    while ( my $file = readdir($dh) ) {
        if ( $file =~ /^\Q$matchname\E/ ) {
            next if ( $file eq '..' || $file eq '.' );
            next if ( $skipreserved and defined $reserved{$file} );
            if ($dirsonly) {
                next if ( !-d $dir . '/' . $file );
            }
            my $filename = $basedir . '/' . $file;
            $filename =~ s/^\///g;
            if ( !$html ) {
                push @matches, { file => $filename };
            }
            else {
                push @matches, { file => Cpanel::Encoder::Tiny::safe_html_encode_str($filename) };
            }
        }
    }
    closedir($dh);

    $result->data( \@matches );
    return 1;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _has_filter_or_sort_key
# Desc:
#   Tests if any of the filter or sort arguments are for the specified fields.
# Arguments:
#   args - Cpanel::Args object - arguments passed to the API call.
#   filter_or_sort_keys - Array Ref - reference to an array of keys for sort or filter from
#   the API calls metadata field.
#   fields - Array Ref - fields to look for in the arguments.
# Returns:
#-------------------------------------------------------------------------------------------------
sub _has_filter_or_sort_key {
    my ( $args, $filter_or_sort_keys, $fields ) = @_;
    my $filter_or_sort_by_match = 0;
    foreach my $key ( @{$filter_or_sort_keys} ) {
        foreach my $field ( @{$fields} ) {
            if ( index( $args->get($key), $field ) != -1 ) {
                $filter_or_sort_by_match = 1;
                last;
            }
        }
        last if $filter_or_sort_by_match;
    }
    return $filter_or_sort_by_match;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _package_file_information
# Desc:
#   Looks up all the related data for a file and packages it for use in get_file_information
#   and list_files.
# Arguments:
#   A hash containing the following:
#   safe_file    - string - safe file name
#   safe_dir     - string - safe directory path
#   show_hidden  - bool - hidden files start with the '.'. If this flag is true, hidden files will
#       be included in the listing. If false, the call will fall-back to the value in the showdotfiles
#       cookie, otherwise it will not show hidden files.  Defaults to false.
#   include_mime - bool - Since mime-types are expensive to calculate, this flag allows callers to
#       decide to load the mime type data in the results. Set to true to include the mime-type of the file
#       in the returned information and false to not add the mime-type to the returned information. Note:
#       if you include a filter or sort by mime-type, it will force this field to be calculated regardless
#       of this flag.
#   mime_types   - array ref - Optional list of mime types to include in the results. If undef, all mime
#       types are returned.
#   raw_mime_types - string - Optional list of raw mime types to include in the results. If not provided,
#       all mime types are will be returned.  If included, this has the effect of setting include_mime to
#       true as well, causing the mime types to be loaded into the records.
#   include_hash - bool - Since hashes are expensive to calculate, hash generation is disabled by default.
#       If true will generate a hash based on the file name and add it to the returned results.
#       If false, will not generate the hash or include it in the results.
#   include_permissions - bool - If true will parse out the owner read and write permission for the file or directory
#       and add it to the returned results. If false, will not parse or write these to the results.
#   include_group - bool - If true will provide the group name in the returned data.
#   include_user  - bool - If true will provide the user name in the returned data.
#   check_for_leaf_directories - bool - Since determining if a directory contains other directories
#       is expensive, this flag provides callers the ability to not check this condition. Pass a true
#       value to run the check and add the isleaf attribute to each item in the returned information,
#       or false to not run the check. Defaults to false.
#   types - array - optional list of file types. If not provided all file types will
#       be returned. Limited to:
#           file - include files
#           dir - include directories
#           char - include char
#           block - include block
#           fifo - include fifo
#           link - include links
#           socket - include sockets
#   parent_hash - string - hash of the parent folder name.
# Returns:
#   The info object for the file or folder with the following fields:
#
#       fullpath  - string - full path to the file
#       path      - string - path only not include the file name or directory name
#       file      - string - file name or directory name
#       uid       - number - system user id of the owner of the file
#       gid       - number - system group id of the owner of the file.
#       size      - number - size of the file in bytes.
#       mtime     - timestamp - time the file was last modified
#       humansize - string - formated size of the file:  1K 1M 10M 45G
#       nicemode  - string - formatted file system mode.
#       mode      - number - mode from the stat of the file,
#       ctime     - timestamp - time the file was created
#       type      - string - type of the item (file, dir, char, block, fifo, link, socket)
#       absdir    - string - legacy field
#       mimetype  - string - Contains the mime type of the file. Only included if the include_mime
#           flag is true.
#       rawmimetype - string - Actual mime type of the file. Only included if the include_mime
#           flag is true.
#       isleaf    - bool - only provided in directory objects, true if the directory does not
#       have any sub-directories. False if it does contain one or more sub-directories.  Only
#           included if the check_leaf flag is true.
#       hash      - string - hash of the full path for the file or directory.  Only included if the
#           include_hash flag is  true.
#       phash     - string - hash of the parent path for the file or directory. Only included if the
#           include_hash flag is  true.
#       read      - bool - true if the file can be read, false otherwise. Only included if the
#           include_permissions flag is true.
#       write     - bool - true if the file can be written, false otherwise. Only included if the
#           include_permissions flag is true.
#       user      - string - actual user name. Only provided if the include_user flag is set.
#       group     - string - actual group name. Only provided if the include_group flag is set.
#-------------------------------------------------------------------------------------------------
sub _package_file_information {

    my %args = @_;
    my ( $safe_file, $safe_dir, $safe_abs_dir )                      = ( @args{qw/safe_file safe_dir safe_abs_dir/} );
    my ( $show_hidden, $include_hash, $parent_hash )                 = ( @args{qw/show_hidden include_hash parent_hash/} );
    my ( $include_mime, $mime_types, $raw_mime_types )               = ( @args{qw/include_mime mime_types raw_mime_types/} );
    my ( $check_for_leaf_directories, $types, $include_permissions ) = ( @args{qw/check_for_leaf_directories types include_permissions/} );
    my ( $include_user, $include_group )                             = ( @args{qw/include_user include_group/} );
    my ( $error, $exist, %FINFO );

    # ??? This seems kind of confusing
    my ( $file_name, $safe_full_path, $safe_path ) = _split_file_path( $safe_file, $safe_dir );

    # Conditionally skip hidden files.
    if ( !$show_hidden && $file_name =~ /^\./ ) {

        # Skip hidden files
        $error = $locale->maketext( 'The file “[_1]” requested is a hidden file, but you are not showing hidden files.', $file_name );
        return ( 1, 0, $error );
    }

    my $absdir = Cwd::abs_path($safe_dir) || $safe_dir;

    my ( $mime_type, $mime_name, $raw_mime_type, $raw_mime_name, $file_type );

    # Fetch the stats
    my @stat = lstat($safe_full_path);
    if ( !@stat ) {

        # Skip files we can't stat
        $error = $locale->maketext( 'The file “[_1]” is not available.', $file_name );

        %FINFO = (
            'fullpath'  => $safe_full_path,
            'path'      => $safe_path,
            'file'      => $file_name,
            'uid'       => undef,
            'gid'       => undef,
            'size'      => undef,
            'mtime'     => undef,
            'humansize' => undef,
            'nicemode'  => undef,
            'mode'      => undef,
            'ctime'     => undef,
            'type'      => undef,
            'absdir'    => $absdir,
            'exists'    => 0,
        );
    }
    else {
        $exist = -e _ ? 1 : 0;
        if ( !$exist ) {
            $error = $locale->maketext( 'The file “[_1]” does not exist in the requested directory “[_2]”.', $file_name, $safe_dir );
        }

        # Conditionally skip file types not in the requested list
        $file_type = $FILE_TYPES{ $stat[2] & $Cpanel::Fcntl::Constants::S_IFMT };
        if ( $types && !( grep { $file_type eq $_ } @{$types} ) ) {

            # Skip types we don't care about
            return ( 1, 0, 0 );
        }

        # Filter by mime type
        if ($include_mime) {
            ( $mime_type, $mime_name, $raw_mime_type, $raw_mime_name ) = Cpanel::Fileman::Mime::get_mime_type( $safe_path, $file_name, $file_type, $MIME_TYPES, 1 );

            # Filter by cpanel mime type
            if ( $mime_types && !( grep { $mime_type eq $_ } @{$mime_types} ) ) {

                # Skip cpanel mapped mime types we don't care about
                return ( 1, 0, 0 );
            }

            # Filter by actual mime type
            if ( $raw_mime_types && !( grep { $raw_mime_type eq $_ } @{$raw_mime_types} ) ) {

                # Skip actual mime types we don't care about
                return ( 1, 0, 0 );
            }
        }

        %FINFO = (
            'fullpath'  => $safe_full_path,
            'path'      => $safe_path,
            'file'      => $file_name,
            'uid'       => $stat[4] || '',
            'gid'       => $stat[5] || '',
            'size'      => $stat[7] || '',
            'mtime'     => $stat[9] || '',
            'humansize' => ( $MEMORIZED_SIZES{ $stat[7] } ||= Cpanel::Math::_toHumanSize( $stat[7] ) ),
            'nicemode'  => sprintf( "%04o", ( $stat[2] & 07777 ) ),
            'mode'      => $stat[2]  || '',
            'ctime'     => $stat[10] || '',
            'type'      => $file_type,
            'absdir'    => $absdir,
            'exists'    => $exist,
        );
    }

    if ( $include_hash && defined $parent_hash ) {
        $FINFO{'hash'}  = Cpanel::ElFinder::Encoder::encode_path($safe_full_path);
        $FINFO{'phash'} = $parent_hash;
    }

    if ($include_permissions) {
        $FINFO{'read'}  = !@stat ? undef : ( $stat[2] & 00400 ) == 00400 ? 1 : 0;    # S_IRUSR = 00400 owner has read permission
        $FINFO{'write'} = !@stat ? undef : ( $stat[2] & 00200 ) == 00200 ? 1 : 0;    # S_IWUSR = 00200 owner has write permission
    }

    if ($include_group) {
        $FINFO{'group'} = !@stat ? undef : ( getgrgid( $stat[5] ) )[0];
    }

    if ($include_user) {
        $FINFO{'user'} = !@stat ? undef : ( Cpanel::PwCache::getpwuid( $stat[4] ) )[0];
    }

    if ($include_mime) {
        $FINFO{'mimetype'}    = $mime_type     || undef;
        $FINFO{'mimename'}    = $mime_name     || undef;
        $FINFO{'rawmimetype'} = $raw_mime_type || undef;
        $FINFO{'rawmimename'} = $raw_mime_name || undef;
    }

    if ( length $file_type && $file_type eq 'dir' ) {
        if ($check_for_leaf_directories) {
            $FINFO{'isleaf'} = _does_folder_contain_directories( $safe_full_path, $show_hidden );
        }
    }

    return ( 0, \%FINFO, $error );
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _get_files_from_form
# Desc:
#   Retrieves the files from the form.
# Arguments:
#   N/A
# Returns:
#   List of files.
#-------------------------------------------------------------------------------------------------
sub _get_files_from_form {
    my @FILES;
    foreach my $file ( keys %Cpanel::FORM ) {
        next if ( $file !~ /^filepath-/ );
        push( @FILES, $Cpanel::FORM{$file} );
    }
    return @FILES;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _does_folder_contain_directories
# Desc:
#   Tests if the passed in folder contains any directories
# Arguments:
#   path - string - path to a directory
#   show_hidden - bool - if true will include hidden files, if false, will exclude hidden folders.
# Returns:
#   bool - true if the directory contains other directories, false if it does not.
#-------------------------------------------------------------------------------------------------
sub _does_folder_contain_directories {
    my ( $path, $show_hidden ) = @_;

    $show_hidden = defined $show_hidden ? $show_hidden : $SHOW_HIDDEN_DEFAULT;

    my $is_leaf = 1;
    opendir( my $ld, $path );
    while ( my $file = readdir($ld) ) {
        if ($show_hidden) {
            if ( $file !~ /^\.\.?$/ && -d $path . '/' . $file ) {
                $is_leaf = 0;
                last;
            }
        }
        elsif ( $file !~ /^\.\.?/ && -d $path . '/' . $file ) {
            $is_leaf = 0;
            last;
        }
    }
    closedir($ld);
    return $is_leaf;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _split_file_parts
# Desc:
#   Will sanitize the file name parts.
# Arguments:
#   string - file name part as passed in.
#   string - directory part as passed in.
# Returns:
#   string - file name part sanitized.
#   string - full path.
#   string - directory part sanitized.
#-------------------------------------------------------------------------------------------------
sub _split_file_path {
    my ( $file, $dir ) = @_;
    my ( @file_parts, $file_name, $file_dir );

    $file = '' if !length $file;
    if ( $file =~ tr/\/// ) {
        @file_parts = split( /\//, $file );
        $file_name  = pop(@file_parts);
        $file_dir   = Cpanel::SafeDir::safedir( join( '/', @file_parts ) );
        return ( $file_name, $file_dir . '/' . $file_name, $file_dir );
    }
    else {
        return ( $file, $dir . ( $file ? '/' . $file : '' ), $dir );
    }
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _initialize_home_directory
# Desc:
#   Initialize the home directory folder state in case it has not been done yet.
# Arguments:
#   N/A
# Returns:
#   N/A
#-------------------------------------------------------------------------------------------------
sub _initialize_home_directory {
    if ( !-e "$Cpanel::abshomedir/.trash" ) {
        return mkdir "$Cpanel::abshomedir/.trash", 0700;
    }
    return 1;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _extract_directory_and_leaf_resource
# Desc:
#   Extracts the final complete resource from a path. If there is a trailing /, it is removed
#   before processing.
# Examples:
#   _extract_directory_and_leaf_resource('/home/abc/tom.txt'); # returns ( '/home/abc', 'tom.txt' )
#   _extract_directory_and_leaf_resource('/home/abc');         # returns ( '/home', 'abc' );
#   _extract_directory_and_leaf_resource('/home/abc/');        # returns ( '/home', 'abc' );
#   _extract_directory_and_leaf_resource('home/abc');          # returns ( 'home', 'abc' );
# Arguments:
#   string - Path to process
# Returns:
#   Final complete resource in the path.
#-------------------------------------------------------------------------------------------------
sub _extract_directory_and_leaf_resource {
    my ($path) = @_;
    $path = '' if !length $path;
    my @parts = split( '/', Cpanel::StringFunc::Trim::rtrim( $path, '/' ) );
    my $leaf  = pop(@parts);
    my $dir   = join( '/', @parts );
    return ( $dir, $leaf );
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _initialize
# Desc:
#   initialize the logger and local system if they are not already initialized.
# Arguments:
#   N/A
# Returns:
#   N/A
#-------------------------------------------------------------------------------------------------
sub _initialize {
    $logger ||= Cpanel::Logger->new();
    $locale ||= Cpanel::Locale->get_handle();
    return 1;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _get_cookies
# Desc:
#   Retrieve the cookies. Used to help build the tests.
# Arguments:
#   N/A
# Returns:
#   hash - Cookies for this call.
#-------------------------------------------------------------------------------------------------
sub _get_cookies {
    return \%Cpanel::Cookies;
}

1;
