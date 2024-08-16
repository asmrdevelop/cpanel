package Cpanel::MagicRevision;

# cpanel - Cpanel/MagicRevision.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::App             ();
use Cpanel::Binary          ();
use Cpanel::ConfigFiles     ();
use Cpanel::JS::Variations  ();
use Cpanel::Path::Normalize ();
use Cpanel::StatCache       ();

use constant NON_MAGIC_URLS_TOUCHFILE_PATH => '/var/cpanel/conf/USE_NON-MAGIC_URLS';

my %URI_CACHE;
my $cpanel_binary_mtime;

our $MAGIC_PREFIX = '/cPanel_magic_revision_';

our $USE_NON_MAGIC_URLS;

#For testing
our $_WHM_BASE    = "$Cpanel::ConfigFiles::CPANEL_ROOT/whostmgr/docroot";
our $_CPANEL_BASE = "$Cpanel::ConfigFiles::CPANEL_ROOT/base";

sub cache_clear {
    %URI_CACHE = ();
    undef $USE_NON_MAGIC_URLS;
    return;
}

sub MagicRevision_uri {
    print calculate_theme_relative_magic_url(shift);
}

sub get_docroot {
    return ( index( $Cpanel::App::appname, 'whostmgr' ) > -1 && $Cpanel::App::context ne 'unauthenticated' )
      ? $_WHM_BASE
      : $_CPANEL_BASE;
}

#This function ALTERS THE ORIGINAL.
sub strip_prefix { return if index( $_[0], $MAGIC_PREFIX ) == -1; $_[0] =~ s{\A/*$MAGIC_PREFIX[0-9.]+}{}o; return 1; }

## cpdev: this is what '<cpanel MagicRevision="uri("images/logaccess.gif")">' calls
sub calculate_theme_relative_magic_url {    ## no critic qw(Subroutines::RequireArgUnpacking)
    return $URI_CACHE{ $_[0] } if $URI_CACHE{ $_[0] };
    my ( $file, $url ) = calculate_theme_relative_file_path_and_url( $_[0] );
    my $magicnum = ( ( $Cpanel::appname eq 'webmail' || $Cpanel::appname eq 'cpanel' ) ? Cpanel::StatCache::cachedmtime( $file, ( $cpanel_binary_mtime ||= Cpanel::StatCache::cachedmtime('/usr/local/cpanel/cpanel') ) ) : Cpanel::StatCache::cachedmtime($file) );

    $URI_CACHE{ $_[0] } = $MAGIC_PREFIX . ( $magicnum || 0 ) . '/' . $url;
    $URI_CACHE{ $_[0] } =~ tr{/}{}s;        # squash dupes
    return $URI_CACHE{ $_[0] };
}

sub calculate_theme_relative_file_path {
    return ( calculate_theme_relative_file_path_and_url( $_[0] ) )[0];
}

sub calculate_theme_relative_file_path_and_url {
    my $basepath = index( $_[0], '/' ) != 0 ? ( ( $Cpanel::appname eq 'webmail' ? '/webmail/' : '/frontend/' ) . $Cpanel::CPDATA{'RS'} . '/' ) : '';
    return ( $_CPANEL_BASE . $basepath . $_[0], $basepath . $_[0] );
}

my %TRIM_CHRS = ( ' ' => 1, "\t" => 1, "\r" => 1, "\n" => 1, "\f" => 1, q{'} => 1, q{"} => 1 );

sub _normalize_url {
    my $uri = $_[0];
    if ( $uri =~ tr/\ \t\r\n\f'"// ) {
        chop($uri) while $TRIM_CHRS{ substr( $uri, -1 ) };
    }

    $uri =~ tr{/}{}s;    #important: squash repeated foreslashes

    return $uri;
}

## cpdev: this is what is available to TT via the "MagicRevision" call
sub calculate_magic_url {
    return calculate_magic_url_or_nothing(@_) || _normalize_url( $_[0] );
}

#args
# document     - string - document being processed.
# query_string - string - optional query string from the request.
sub calculate_lex {
    my ( $document, $query_string ) = @_;
    return if !$document || !$query_string;       # quickest exit.
    return if substr( $document, -3 ) ne '.js'    # not js document
      || !(
        index( $query_string, 'locale=' ) == 0    # does not have a locale in the query string
        || index( $query_string, '&locale=' ) > -1
      );

    my ( $locale, $localized_file ) = ( '', '' );
    require Cpanel::HTTP::QueryString;
    my $query_hr = Cpanel::HTTP::QueryString::parse_query_string_sr( \$query_string );
    if ( $query_hr->{'locale'} && $query_hr->{'locale'} !~ tr{0-9a-zA-Z_-}{}c ) {
        $locale         = $query_hr->{'locale'};
        $localized_file = Cpanel::JS::Variations::lex_filename_for( $document, $locale );
    }
    return ( $locale, $localized_file );
}

#args:
#   uri
#   relative uri (default $ENV{'REQUEST_URI'} || '/scripts/command')
#   docroot (context-sensitive default; see code)
sub calculate_magic_url_or_nothing {
    my ( $uri, $current_uri, $docroot ) = @_;

    $uri = _normalize_url($uri);
    return $uri if ( $uri eq '/'
        || index( $uri, 'data:' ) == 0
        || ( index( $uri, $MAGIC_PREFIX ) >= 0 && $uri =~ m</*${MAGIC_PREFIX}[\.0-9]+/+>o ) );

    ( $uri, my $query_string ) = split( m{\?}, $uri, 2 );

    my ( $locale, $localized_file, $uri_key );
    if ($query_string) {
        ( $locale, $localized_file ) = calculate_lex( $uri, $query_string );
        $uri_key = $locale ? $uri . "-$locale" : $uri;
    }
    else {
        $uri_key = $uri;
    }

    if ( $URI_CACHE{$uri_key} ) {
        return $query_string ? $URI_CACHE{$uri_key} . '?' . $query_string : $URI_CACHE{$uri_key};
    }

    $current_uri ||= $ENV{'REQUEST_URI'} || '/scripts/command';
    $docroot     ||= get_docroot();

    ($current_uri) = split( m{\?}, $current_uri, 1 );                               #faster s/\?.*//g;
    $current_uri =~ s{\A/cpsess[^/]+}{} if index( $current_uri, '/cpses' ) > -1;    #$Cpanel::Session::token_prefix strip
    strip_prefix($current_uri);

    if ( !Cpanel::Binary::is_binary() ) {
        if ( !defined $USE_NON_MAGIC_URLS ) {
            $USE_NON_MAGIC_URLS = -e NON_MAGIC_URLS_TOUCHFILE_PATH ? 1 : 0;
        }
        if ($USE_NON_MAGIC_URLS) {

            # only return the uri *IF* the file exists #
            if ( -e "${docroot}${uri}" ) {
                $URI_CACHE{$uri_key} = $uri;
                return $query_string ? $URI_CACHE{$uri_key} . '?' . $query_string : $URI_CACHE{$uri_key};
            }

            # because otherwise we have to return undef #
            return;
        }
    }

    my $file;
    if ( index( $uri, '/' ) == 0 ) {
        $file = $docroot . $uri;
    }
    elsif ($current_uri) {
        my @PATH = split( /\/+/, $current_uri );
        pop(@PATH);
        my $uri_dir = join( '/', @PATH );
        $file = $docroot . '/' . $uri_dir . '/' . $uri;
    }
    else {
        $file = $docroot . '/' . $uri;
    }

    $file =~ tr{/}{}s;    # collapse //s to /

    my $magic_revision_prefix = get_magic_revision_prefix( $file, $locale ) or return;

    {                     # sanitize the file and make sure its in the docroot
        my $unmodified_file = $file;
        if ( index( $file, '..' ) > -1 ) {

            #We don’t want to do abs_path() here because that would resolve
            #symlinks, which would make WebMail try to load files from cPanel,
            #which will fail and lead to broken images in the UI.
            $file = Cpanel::Path::Normalize::normalize($file);
        }
        $file = $docroot . $file if index( $file, $docroot ) != 0;    # Always make sure the file is in the docroot
        $file =~ tr{/}{}s;                                            # collapse //s to /

        # only recalculate the magic revision prefix if our sanitization modified it
        if ( $unmodified_file ne $file ) {
            $magic_revision_prefix = get_magic_revision_prefix( $file, $locale ) or return;
        }
    }

    $URI_CACHE{$uri_key} = $magic_revision_prefix . '/' . substr( $file, length($docroot) + 1 );

    return $query_string ? $URI_CACHE{$uri_key} . '?' . $query_string : $URI_CACHE{$uri_key};
}

#takes a system path and returns just the magic revision prefix
my %_Cached_Prefixes;

sub get_magic_revision_prefix {
    my ( $file, $locale ) = @_;
    return if !$file;

    my $prefix_key = $locale ? "$file-$locale" : $file;
    return $_Cached_Prefixes{$prefix_key} if defined $_Cached_Prefixes{$prefix_key};
    my $mtime = get_magic_revision_mtime($file);
    if ($locale) {

        # These will be slip-streamed, so we want to use the
        # newest of the two files
        my $lmtime = get_magic_revision_lex_mtime($locale);
        if ( $lmtime && $lmtime > $mtime ) {
            $mtime = $lmtime;
        }
    }

    if ($mtime) {
        return $_Cached_Prefixes{$prefix_key} = $MAGIC_PREFIX . $mtime;
    }
    else {
        return;
    }
}

sub get_magic_revision_mtime {
    return ( $Cpanel::appname && ( $Cpanel::appname eq 'webmail' || $Cpanel::appname eq 'cpanel' ) )
      ? Cpanel::StatCache::cachedmtime( $_[0], ( $cpanel_binary_mtime ||= Cpanel::StatCache::cachedmtime('/usr/local/cpanel/cpanel') ) )
      : Cpanel::StatCache::cachedmtime( $_[0] );
}

sub get_magic_revision_lex_mtime {
    my ($locale) = @_;
    $locale = 'en' if !defined $locale;

    my $locale_build_mtime = Cpanel::StatCache::cachedmtime("/var/cpanel/locale/$locale.cdb");

    return $locale_build_mtime;
}

1;
