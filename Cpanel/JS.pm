package Cpanel::JS;

# cpanel - Cpanel/JS.pm                            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::StatCache     ();
use Cpanel::MagicRevision ();

=head1 NAME

Cpanel::JS

=head1 DESCRIPTION

THIS FUNCTION IS deprecated AND WILL BE REMOVED IN THE FUTURE. get_cjt_url
is always localized now

JavaScript support functions. Primarily used to fetch URLs for JavaScript files and
for legacy applications <script> tags for those urls.

=head2 get_cjt_lex_script_tag

=head3 Purpose

Genererates a script tag for the CJT 1.0 library for x3. Do not use in any context other
then pages that use the cPanel parser.

=head3 Arguments

  locale - object - optional locale, will be filled in with the current users locale if not provided.
  return_url - boolean - optional, will return the url instead of the script tag if truthy.

=head3 Returns

  string - Fully formed script tag if the url exists, otherwise returns an empty string.

=cut

sub get_cjt_lex_script_tag {
    return '';    # no longer needed since get_cjt_url is localized
}

=head2 get_cjt_url

=head3 Purpose

Fetch the url for cpanel-all.js based on whats available on the system.

=head3 Arguments

locale   - object - optional locale, will be filled in with the current users locale if not provided.

=head3 Returns

Returns the url to the cpanel-all.js derived file. Will be the optimized version if
available. If not falls back to the unoptimized one.  If the locale is available
?locale=TAG will be appended and dynamically included by cpsrvd

=cut

sub get_cjt_url {
    my ( $locale, $debug ) = @_;

    my $cjt_url;
    if ( !$locale ) {
        require Cpanel::Locale;
        $locale = Cpanel::Locale->get_handle();
    }

    my $root = _root_dir();
    if ( !$debug && Cpanel::StatCache::cachedmtime("$root/base/cjt/cpanel-all-min.js") ) {
        $cjt_url = Cpanel::MagicRevision::calculate_magic_url('/cjt/cpanel-all-min.js');
    }
    else {
        $cjt_url = Cpanel::MagicRevision::calculate_magic_url('/cjt/cpanel-all.js');
    }

    if ( get_js_lex_app_full_path( $locale, "base/cjt/cpanel-all.js", 'base' ) ) {
        my $locale_tag = ref $locale ? $locale->get_language_tag() : $locale;
        return _append_locale_revision( $cjt_url, $locale_tag );
    }

    return $cjt_url;
}

=head2 get_cjt_lex_url

=head3 Purpose

Fetch the url for the lexicon for cpanel-all.

=head3 Returns

Returns the url for the related lexicon file or empty string if not available.

=cut

*get_cjt_lex_url = \&get_cjt_url;

=head2 get_js_lex_script_tag

=head3 Purpose

Gets the lexicon script tag for the passed locale and path. Do not use in any context other
then pages that use the cPanel parser.

=head3 Arguments

  locale   - object - optional locale, will be filled in with the current users locale if not provided.
  path     - string - required path to the source file that is related to the lexicon file we want to retrieve.
  rel_root - string - optional alternative root path. Bypasses application path logic if provided.
  return_url - boolean - optional, will return the url instead of the script tag if truthy.

=head3 Returns

Returns the script tag for the app relative url to the lexicon file or an empty string if the lexicon file is not available.

=cut

sub get_js_lex_script_tag {
    my ( $locale, $path, $rel_root, $return_url ) = @_;
    my $uri = get_js_lex_url( $locale, $path, $rel_root );
    return $uri if $return_url;
    return _format_script_tag($uri);
}

=head2 get_js_lex_url

=head3 Purpose

Fetch the url for the lexicon file for the requested file and the passed locale.

=head3 Arguments

  locale   - object - optional locale, will be filled in with the current users locale if not provided.
  path     - string - required path to the source file that is related to the lexicon file we want to retrieve.
  rel_root - string - optional alternative root path. Bypasses application path logic if provided.

=head3 Returns

Returns the app relative url to the lexicon file or an empty string if the lexicon file is not available.

=cut

sub get_js_lex_url {
    my ( $locale, $path, $rel_root ) = @_;
    substr( $path, 3, 4, '' ) if index( $path, 'js2-min' ) == 0;    # strip -min
    my $lex_path = get_js_lex_app_full_path( $locale, $path, $rel_root );
    if ($lex_path) {
        $lex_path = _adjust_path_for_app_uri( $lex_path, $rel_root );

        if ( !$locale ) {
            require Cpanel::Locale;
            $locale = Cpanel::Locale->get_handle();
        }
        $lex_path = _append_locale_revision( $lex_path, $locale->get_language_tag(), 1 );
        return Cpanel::MagicRevision::calculate_magic_url($lex_path);
    }
    return '';
}

=head2 get_js_localized_url

=head3 Purpose

Provides the localized version of the URL for the specified file and locale combination if an associated lexicon file exists.

=head3 Arguments

  locale        - object - optional locale, will be filled in with the current users locale if not provided.
  original_path - string - required path to the source file that is related to the lexicon file we want to retrieve.
  rel_root      - string - optional alternative root path. Bypasses application path logic if provided.

=head3 Returns

Returns the magic URL for the file with the appropriate locale query string, if a lexicon file is found.

=cut

sub get_js_localized_url {
    my ( $locale, $original_path, $rel_root ) = @_;

    return unless defined $original_path;

    # Get the magic revision ready
    my $final_url = ( $original_path =~ m{$Cpanel::MagicRevision::MAGIC_PREFIX\d+/}o ? $original_path : Cpanel::MagicRevision::calculate_magic_url($original_path) );

    # Adjust the original path to see if we can find a lex file
    my $lex_path = $original_path;
    substr( $lex_path, 3, 4, '' ) if index( $lex_path, 'js2-min' ) == 0;    # strip -min
    $lex_path =~ s{$Cpanel::MagicRevision::MAGIC_PREFIX\d+/}{/}o;
    $lex_path = get_js_lex_app_full_path( $locale, $lex_path, $rel_root );

    # Add the query args if we have a lex file that needs to be slipstreamed later
    if ($lex_path) {
        if ( !$locale ) {
            require Cpanel::Locale;
            $locale = Cpanel::Locale->get_handle();
        }

        $final_url = _append_locale_revision( $final_url, $locale->get_language_tag() );
    }

    return $final_url;
}

=head2 get_js_lex_app_full_path

=head3 Purpose

Fetch the full path for the lexicon file for the requested file and the passed locale.

=head3 Arguments

  locale   - object - optional locale, will be filled in with the current users locale if not provided.
  path     - string - required path to the source file that is related to the lexicon file we want to retrieve.
  rel_root - string - optional alternative root path. Bypasses application path logic if provided.

=head3 Returns


Returns the path to the lexicon if it exists. Otherwise, returns an empty string.

=cut

sub get_js_lex_app_full_path {
    my ( $locale, $path, $rel_root ) = @_;

    $path = _get_full_file_path( $path, $rel_root );

    if ( !$locale ) {
        require Cpanel::Locale;
        $locale = Cpanel::Locale->get_handle();
    }

    return $locale->cpanel_get_lex_path($path) || '';
}

=head2 get_js_lex_app_rel_path

=head3 Purpose

Fetch the app relative path for the lexicon file as needed by the INSERT template
toolkit directive for the requested file and the passed locale.

=head3 Arguments

  locale   - object - optional locale, will be filled in with the current users locale if not provided.
  path     - string - required path to the source file that is related to the lexicon file we want to retrieve.
  rel_root - string - optional alternative root path. Bypasses application path logic if provided.

=head3 Returns

Returns the application relative path to the lexicon if it exists. Otherwise, returns an empty string.

=cut

sub get_js_lex_app_rel_path {
    my ( $locale, $path, $rel_root ) = @_;
    my $full_lex_path = get_js_lex_app_full_path( $locale, $path, $rel_root );
    my $rel_lex_path  = _adjust_path_for_app_uri( $full_lex_path, $rel_root );

    my $appname = $Cpanel::appname;
    my $search;
    if ( index( $appname, 'cpanel' ) == 0 ) {
        $search = '/frontend/' . $Cpanel::CPDATA{'RS'} . '/';
        $rel_lex_path =~ s{\Q$search\E}{};
    }
    elsif ( index( $appname, 'webmail' ) == 0 ) {
        $search = '/webmail/' . $Cpanel::CPDATA{'RS'} . '/';
        $rel_lex_path =~ s{\Q$search\E}{};
    }

    # Remove any leading / since we always want relative
    substr( $rel_lex_path, 0, 1, '' ) if index( $rel_lex_path, '/' ) == 0;

    return $rel_lex_path;
}

sub _append_locale_revision {
    my ( $path, $locale_tag, $no_locale ) = @_;
    return $path if !$locale_tag;

    my $locale_version = Cpanel::MagicRevision::get_magic_revision_lex_mtime($locale_tag);

    my $query = '';
    $query = 'locale=' . $locale_tag . '&' if !$no_locale;
    $query .= 'locale_revision=' . $locale_version;
    return $path . '&' . $query if index( $path, '?' ) > -1;
    return $path . '?' . $query;
}

sub _get_full_file_path {
    my ( $path, $rel_root ) = @_;

    $path     =~ tr{.}{}s;
    $rel_root =~ tr{.}{}s if $rel_root;

    my $root = _root_dir();

    if ($rel_root) {
        $path = $root . '/' . $path;
    }
    else {
        my $appname = $Cpanel::appname // 'whostmgr';
        my $_base_path;
        if ( index( $appname, 'whostmgr' ) == 0 ) {
            $_base_path = $root . '/whostmgr/docroot/';
        }
        elsif ( index( $appname, 'cpanel' ) == 0 ) {
            $_base_path = $root . '/base/frontend/' . $Cpanel::CPDATA{'RS'} . '/';
        }
        elsif ( index( $appname, 'webmail' ) == 0 ) {
            $_base_path = $root . '/base/webmail/' . $Cpanel::CPDATA{'RS'} . '/';
        }

        if ( $_base_path && $path !~ m/^\Q$_base_path\E/ ) {
            $path = $_base_path . $path;
        }
    }

    return $path;
}

sub _adjust_path_for_app_uri {
    my ( $path, $rel_root ) = @_;
    my $root    = _root_dir();
    my $appname = $Cpanel::appname || $Cpanel::App::appname;

    if ($rel_root) {
        $path =~ s{\Q$root/$rel_root\E}{};
    }
    elsif ( index( $appname, 'whostmgr' ) == 0 ) {
        $path =~ s{\Q$root\E/whostmgr/docroot}{};
    }
    elsif ( index( $appname, 'webmail' ) == 0 || index( $appname, 'cpanel' ) == 0 ) {
        $path =~ s{\Q$root\E/base}{};
    }

    return $path;
}

# for testing mainly
sub _root_dir {
    return '/usr/local/cpanel';
}

sub _format_script_tag {
    my ($uri) = @_;
    return '' if !$uri;
    require Cpanel::Encoder::Tiny;
    return '<script type="text/javascript" src="' . Cpanel::Encoder::Tiny::safe_html_encode_str($uri) . '"></script>';
}

1;
