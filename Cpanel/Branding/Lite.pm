package Cpanel::Branding::Lite;

# cpanel - Cpanel/Branding/Lite.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Debug                   ();
use Cpanel::Encoder::Tiny           ();
use Cpanel::Encoder::URI            ();
use Cpanel::GlobalCache             ();
use Cpanel::Debug                   ();
use Cpanel::Path::Safety            ();
use Cpanel::PwCache                 ();
use Cpanel::StatCache               ();
use Cpanel::Branding::Lite::Config  ();
use Cpanel::Branding::Lite::Package ();
use Cpanel::ConfigFiles             ();

our @EXTLIST = ( 'jpg', 'gif', 'png', 'ico' );    # ICO must be the list type of we need to alter _image
our $ENOENT  = 2;

my ( $cached_contactinfodir, $cached_real_owner );

## now, also used by Cpanel::API::Branding
our ( %_Image_cache, $_Branding_mtime, $envtype );

sub _clearcache {
    _clear_internal_cache();
    return Cpanel::Branding::Lite::Package::_clearcache();
}

sub _clear_internal_cache {
    %_Image_cache = ();
    undef $_Branding_mtime;
    undef $cached_real_owner;
    undef $cached_contactinfodir;
    return;
}

sub _clear_memory_cache {
    _clear_internal_cache();
    return Cpanel::Branding::Lite::Package::_clear_memory_cache();

}

sub _loadenvtype {

    # Any system with a "standard" (non-vps) license will be treated as a standard system for the purposes of the UI
    return 'standard' if ( !exists $Cpanel::CPFLAGS{'vps'} || !$Cpanel::CPFLAGS{'vps'} );    # CPFLAGS are always mapped to true, so "!$Cpanel::CPFLAGS{'vps'}" is redundant
    return ( $envtype = Cpanel::GlobalCache::loadfile( 'cpanel', '/var/cpanel/envtype' ) || 'standard' );
}

sub _text {
    my $textfile = shift;
    Cpanel::Path::Safety::make_safe_for_path( \$textfile );

    my $ownerhomedir = Cpanel::Branding::Lite::Package::_getbrandingdir();
    my $brandingpkg  = Cpanel::Branding::Lite::Package::_getbrandingpkg();

    local ( $/, *BRANDINGTEXT );

    my $bbasedir = ( $Cpanel::appname eq 'webmail' ) ? 'webmail' : 'frontend';
    my $theme    = $Cpanel::CPDATA{'RS'};

    $_Branding_mtime ||= _getbrandingmtime();
    foreach my $brandingdir (
        "$ownerhomedir/cpanelbranding/$theme",
        "$ownerhomedir/cpanelbranding",
        "/usr/local/cpanel/base/$bbasedir/$theme/branding",
    ) {
        if ( $brandingpkg ne q{} && -d "$brandingdir/$brandingpkg" ) {
            $brandingdir .= "/$brandingpkg";
        }
        if ( Cpanel::StatCache::cachedmtime( "$brandingdir/${textfile}.txt", $_Branding_mtime, { 'warn' => 1 } ) ) {
            if ( open my $bt, '<', "$brandingdir/${textfile}.txt" ) {
                local $/;
                print scalar <$bt>;
                close $bt;
                return q{};
            }
        }
    }

    warn "Unable to load branding for $textfile";

    return q{};
}

sub _file {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)
    my (
        $file,           #1. name of file to include
        $isvar,          #2. return as a variable instead of print
        $brandingpkg,    #3. force a branding package
        $inline,         #4. print the contents of the file inline (value of 2 html-encodes)
        $needfile,       #5. return the name of the file we are looking at
        $skipdefault,    #6. ignore the theme default and only return the branding package
        $checkmain,      #7. check the main branding root for the reseller/root
        $html,           #8. html-encode the output
        $filetype,       #9. return file type instead
    ) = @_;

    $brandingpkg = defined $brandingpkg ? $brandingpkg : Cpanel::Branding::Lite::Package::_getbrandingpkg();
    my $is_root_branding = !length $brandingpkg;

    Cpanel::Path::Safety::make_safe_for_path( \$file );
    Cpanel::Path::Safety::make_safe_for_path( \$brandingpkg );

    if ( !defined $envtype ) { _loadenvtype(); }
    my $isvps        = ( $envtype && $envtype ne 'standard' ) ? 1 : 0;
    my $ownerhomedir = Cpanel::Branding::Lite::Package::_getbrandingdir();

    my $appname = ( ( $Cpanel::appname eq 'webmail' ) ? 'webmail' : 'frontend' );
    my ( $basefile, $ext ) = ( $file =~ m{\A(.*)\.([^\.]+)\z} );

    my @LOCS;

    my $theme = $Cpanel::CPDATA{'RS'};

    $_Branding_mtime ||= _getbrandingmtime();

    ## case 49050: the following variables were renamed by the directory information they contain;
    ##   it makes the following "push @LOCS" more easy to follow

    my $ulc_base_appname_theme_branding   = "/usr/local/cpanel/base/$appname/$theme/branding";
    my $ownerhomedir_cpanelbranding_theme = "$ownerhomedir/cpanelbranding/$theme";

    my $owner_cpanelbranding_exists       = Cpanel::StatCache::cachedmtime( "$ownerhomedir/cpanelbranding/",    $_Branding_mtime );
    my $owner_cpanelbranding_theme_exists = Cpanel::StatCache::cachedmtime( $ownerhomedir_cpanelbranding_theme, $_Branding_mtime );

    my $ownerhomedir_cpanelbranding_theme_pkg;

    if ( $is_root_branding && $owner_cpanelbranding_exists ) {
        if ($checkmain) {
            push @LOCS, "$ownerhomedir/cpanelbranding/$file";
        }
    }
    else {
        $ownerhomedir_cpanelbranding_theme_pkg = "$ownerhomedir_cpanelbranding_theme/$brandingpkg";

        my $owner_cpanelbranding_theme_pkg_exists = Cpanel::StatCache::cachedmtime( $ownerhomedir_cpanelbranding_theme_pkg, $_Branding_mtime );

        my $ulc_base_appname_theme_branding_pkg = "$ulc_base_appname_theme_branding/$brandingpkg";

        #for vps and opt/accelerated, prioritize these special CSS files
        if ( $ext eq 'css' ) {
            if ($isvps) {
                if ($owner_cpanelbranding_theme_pkg_exists) {
                    push @LOCS,
                      (
                        "$ownerhomedir_cpanelbranding_theme_pkg/${basefile}_vps2.css",
                        "$ownerhomedir_cpanelbranding_theme_pkg/${basefile}_vps.css",
                      );
                }
                push @LOCS,
                  (
                    "$ulc_base_appname_theme_branding_pkg/${basefile}_vps2.css",
                    "$ulc_base_appname_theme_branding_pkg/${basefile}_vps.css",
                  );
            }
            else {
                if ($owner_cpanelbranding_theme_pkg_exists) {
                    push @LOCS, "$ownerhomedir_cpanelbranding_theme_pkg/${basefile}_opt.css";
                }
                push @LOCS, "$ulc_base_appname_theme_branding_pkg/${basefile}_opt.css";
            }
        }

        #check the branding package

        if ( $owner_cpanelbranding_exists && $checkmain ) {
            push @LOCS, "$ownerhomedir/cpanelbranding/$file";
        }

        if ($owner_cpanelbranding_theme_pkg_exists) {
            push @LOCS, "$ownerhomedir_cpanelbranding_theme_pkg/$file";
        }

        push @LOCS, "$ulc_base_appname_theme_branding_pkg/$file";
    }

    #check just the theme
    if ( !$skipdefault || $is_root_branding ) {

        #same condition as above for vps and opt/accelerated
        if ( $ext eq 'css' ) {
            if ($isvps) {
                if ($owner_cpanelbranding_theme_exists) {
                    push @LOCS,
                      (
                        "$ownerhomedir_cpanelbranding_theme/${basefile}_vps2.css",
                        "$ownerhomedir_cpanelbranding_theme/${basefile}_vps.css",
                      );
                }
                push @LOCS,
                  (
                    "$ulc_base_appname_theme_branding/${basefile}_vps2.css",
                    "$ulc_base_appname_theme_branding/${basefile}_vps.css",
                  );
            }
            else {
                if ($owner_cpanelbranding_theme_exists) {
                    push @LOCS, "$ownerhomedir_cpanelbranding_theme/${basefile}_opt.css";
                }
                push @LOCS, "$ulc_base_appname_theme_branding/${basefile}_opt.css";
            }
        }
        if ($owner_cpanelbranding_theme_exists) {
            push @LOCS, "$ownerhomedir_cpanelbranding_theme/$file";
        }
        push @LOCS, "$ulc_base_appname_theme_branding/$file";
    }

    ## dynamic expansion of the '.uapi' extension; if the original URL is .html, we replace @LOCS
    ##   with a lookup of .html and .tt through the chain; for .tt extensions, we stick to .tt
    ##   extensions
    if ( $file =~ m/\.uapi$/ ) {
        my ($context) = ( $ENV{'SCRIPT_NAME'} =~ m/\.(html|tt)$/ );
        $context = '' unless ( defined $context );    ## suppress warnings

        #$context = 'tt' if ($context eq 'tmpl');  ## no longer needed, but retaining for the moment

        if ( $context eq 'tt' ) {
            @LOCS = map {
                s/\.uapi$/.tt/;
                $_;
            } @LOCS;
        }
        else {
            @LOCS = map {
                s/\.uapi$//;
                ( "$_.html", "$_.tt" );
            } @LOCS;
        }
    }

    for my $path (@LOCS) {
        if ( my $magicnum = Cpanel::StatCache::cachedmtime( $path, $_Branding_mtime, { 'warn' => 1 } ) ) {
            if ($filetype) {
                print( ( -l $path && readlink($path) =~ /\.auto.tmpl$/ ) ? 'cpautott' : 'cphtml' );
                return;
            }
            elsif ($needfile) {
                return $path;
            }
            elsif ($inline) {
                if ( open my $loc_fh, '<', $path ) {
                    local ($/);
                    if   ( $inline == 2 ) { print Cpanel::Encoder::Tiny::safe_html_encode_str( readline($loc_fh) ); }
                    else                  { print readline($loc_fh); }
                    close($loc_fh);
                }
                else {
                    Cpanel::Debug::log_warn("Unable to open $path: $!");
                }
                return;
            }
            else {
                my $uri       = $path;
                my $uri_theme = ( $theme =~ m{[^$Cpanel::Encoder::URI::URI_SAFE_CHARS]} ) ? Cpanel::Encoder::URI::uri_encode_str($theme) : $theme;
                if ( !$is_root_branding && $uri =~ m{\A\Q$ownerhomedir_cpanelbranding_theme_pkg\E} ) {
                    my $uri_branding = ( $brandingpkg =~ m{\W} ) ? Cpanel::Encoder::URI::uri_encode_str($brandingpkg) : $brandingpkg;
                    $uri =~ s{\A\Q$ownerhomedir_cpanelbranding_theme_pkg\E}{/branding/$uri_theme/$uri_branding};
                }
                elsif ( !( $uri =~ s{\A\Q$ownerhomedir_cpanelbranding_theme\E}{/branding/$uri_theme} ) ) {
                    $uri =~ s{\A/usr/local/cpanel/base}{};
                }

                $uri = "/cPanel_magic_revision_${magicnum}/$uri";
                $uri =~ tr{/}{}s;    # collapse //s to /

                if ($isvar) {
                    return $uri;
                }
                elsif ($html) {
                    return print Cpanel::Encoder::Tiny::safe_html_encode_str($uri);
                }
                else {
                    return print $uri;
                }
            }
        }
    }

    #if we get here, we didn't find the file

    return if $inline || $needfile;

    my $fake_url;

    if ( $ext eq 'html' || $ext eq 'htm' ) {

        #TODO: Make this 'data:text/html,'
        $fake_url = "/unprotected/broken.$ext";
    }
    elsif ( $ext eq 'css' ) {
        $fake_url = 'data:text/css,';
    }
    else {
        return;
    }

    if ($isvar) {
        return $fake_url;
    }
    else {
        print $fake_url;
    }

    return;
}

sub _contact_file {
    my ($file) = @_;

    #file = name of file to include
    Cpanel::Path::Safety::make_safe_for_path( \$file );
    my $ownerhomedir = Cpanel::Branding::Lite::Package::_getbrandingdir();

    my $bbasedir = ( $Cpanel::appname eq 'webmail' ) ? 'webmail' : 'frontend';
    my $theme    = $Cpanel::CPDATA{'RS'};

    my @LOCS;

    push @LOCS, _get_contactinfodir() . "/$file";

    push @LOCS, "$ownerhomedir/cpanelbranding/$theme/$file";
    push @LOCS, "/usr/local/cpanel/base/$bbasedir/$theme/branding/$file";

    $_Branding_mtime ||= _getbrandingmtime();
    foreach my $path (@LOCS) {
        if ( Cpanel::StatCache::cachedmtime( $path, $_Branding_mtime, { 'warn' => 1 } ) ) {
            return $path;
        }
    }
    return;
}

sub _image {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)
    my (
        $imagefile,          #Arg 1 : Image File
        $isvar,              #Arg 2 : Return the variable instead of printing it
        $brandingpkg,        #Arg 3 : Branding Package to use
        $needfile,           #Arg 4 : Return the file instead of the uri
        $nomagic,            #Arg 5 : Disable calculating the magic revision
        $needboth,           #Arg 6 : Return both the file and uri
        $reqext,             #Arg 7 : Requested Extension
        $skip_logo_check,    #Arg 8 : skip logo check
        $encoding_type       #Arg 9 : html-encode printed output
    ) = @_;

    $brandingpkg = defined $brandingpkg ? $brandingpkg : Cpanel::Branding::Lite::Package::_getbrandingpkg();

    my $is_root_branding = !length $brandingpkg;

    Cpanel::Path::Safety::make_safe_for_path( \$imagefile );
    Cpanel::Path::Safety::make_safe_for_path( \$brandingpkg );

    if ( $imagefile =~ s/\.(jpg|ico|gif|png)$//i ) {
        $reqext = $1;
    }

    my $cache_key   = "$brandingpkg.$imagefile";
    my $path_uri_ar = !$skip_logo_check && $_Image_cache{$cache_key};

    if ( !$path_uri_ar ) {

        #
        # The image is not in the cache at this point
        #
        my $ownerhomedir = Cpanel::Branding::Lite::Package::_getbrandingdir();
        my @LOCS;

        _loadenvtype() if !defined $envtype;    # must be done before the isvps check

        my $appname = ( $Cpanel::appname eq 'webmail' )                                    ? 'webmail' : 'frontend';
        my $isicon  = ( $imagefile =~ m{icon} || ( defined $reqext && $reqext eq 'ico' ) ) ? 1         : 0;
        my $isvps   = ( $envtype && $envtype ne 'standard' )                               ? 1         : 0;
        my $islogo  = ( !$skip_logo_check && $imagefile =~ m{logo}i )                      ? 1         : 0;

        my @LOCAL_EXT_LIST = ( $reqext ? ($reqext) : @EXTLIST );
        if ( !$isicon && !$reqext ) { pop @LOCAL_EXT_LIST; }    # pop off .ico to save some stats if possible

        my $theme = $Cpanel::CPDATA{'RS'};

        ## case 49050: the following variables were renamed by the directory information they contain;
        ##   it makes the following "push @LOCS" more easy to follow

        my $ulc_base_appname_theme_branding   = "/usr/local/cpanel/base/$appname/$theme/branding";
        my $ownerhomedir_cpanelbranding_theme = "$ownerhomedir/cpanelbranding/$theme";

        my $ulc_base_appname_theme_branding_pkg   = "$ulc_base_appname_theme_branding/$brandingpkg";
        my $ownerhomedir_cpanelbranding_theme_pkg = "$ownerhomedir_cpanelbranding_theme/$brandingpkg";

        $_Branding_mtime ||= _getbrandingmtime();
        my $owner_cpanelbranding_theme_pkg_exists = Cpanel::StatCache::cachedmtime( $ownerhomedir_cpanelbranding_theme_pkg, $_Branding_mtime );

        my $owner_cpanelbranding_theme_exists = Cpanel::StatCache::cachedmtime( $ownerhomedir_cpanelbranding_theme, $_Branding_mtime );

        my @dirs;
        if ( !$is_root_branding ) {
            if ($owner_cpanelbranding_theme_pkg_exists) {
                push @dirs, $ownerhomedir_cpanelbranding_theme_pkg;
            }
            push @dirs, $ulc_base_appname_theme_branding_pkg;
        }

        if ($owner_cpanelbranding_theme_exists) {
            push @dirs, $ownerhomedir_cpanelbranding_theme;
        }
        push @dirs, $ulc_base_appname_theme_branding;

        foreach my $cur_dir (@dirs) {
            if ($islogo) {
                if ($isvps) {
                    push @LOCS, ( map { "$cur_dir/${imagefile}_vps2.$_" } @LOCAL_EXT_LIST ), ( map { "$cur_dir/${imagefile}_vps.$_" } @LOCAL_EXT_LIST );
                }
                else {
                    push @LOCS, map { "$cur_dir/${imagefile}_opt.$_" } @LOCAL_EXT_LIST;
                }
            }
            push @LOCS, map { "$cur_dir/${imagefile}.$_" } @LOCAL_EXT_LIST;
        }

        #
        # Now that we have the list of possible locations, we search the list
        #

        foreach my $path (@LOCS) {
            if ( my $magicnum = Cpanel::StatCache::cachedmtime( $path, $_Branding_mtime, { 'warn' => 1 } ) ) {
                my $uri       = Cpanel::Encoder::URI::uri_encode_dirstr($path);
                my $uri_theme = Cpanel::Encoder::URI::uri_encode_str($theme);

                if ( $uri =~ m{\A\Q$ownerhomedir_cpanelbranding_theme_pkg\E} ) {
                    my $uri_branding = Cpanel::Encoder::URI::uri_encode_str($brandingpkg);
                    $uri =~ s{\A\Q$ownerhomedir_cpanelbranding_theme_pkg\E}{/branding/$uri_theme/$uri_branding};
                }
                elsif ( !( $uri =~ s{\A\Q$ownerhomedir_cpanelbranding_theme\E}{/branding/$uri_theme} ) ) {
                    $uri =~ s{\A/usr/local/cpanel/base}{};
                }

                $uri = "/cPanel_magic_revision_${magicnum}/$uri" unless $nomagic;
                $uri =~ tr{/}{}s;    # collapse //s to /

                $_Image_cache{$cache_key} = $path_uri_ar = [ $path, $uri ];
                last;
            }
        }
    }

    if ($path_uri_ar) {
        if ($needboth) {
            return @$path_uri_ar;
        }
        elsif ($needfile) {
            return $path_uri_ar->[0];
        }
        elsif ($isvar) {
            return $path_uri_ar->[1];
        }
        elsif ($encoding_type) {
            if ( $encoding_type == 2 || $encoding_type eq '@' ) {
                return print Cpanel::Encoder::Tiny::css_encode_str( $path_uri_ar->[1] );
            }
            else {
                return print Cpanel::Encoder::Tiny::safe_html_encode_str( $path_uri_ar->[1] );
            }
        }
        else {
            return print $path_uri_ar->[1];
        }
    }
    else {

        #
        # We fall though with a broken image when it is not found
        #
        if ($needfile) {
            return;
        }
        elsif ($isvar) {
            return '/unprotected/broken.gif';
        }
        else {
            return print '/unprotected/broken.gif';
        }
    }
}

sub _get_contactinfodir {
    if ($cached_contactinfodir) { return $cached_contactinfodir; }

    $cached_real_owner ||= $Cpanel::CPDATA{'OWNER'} eq $Cpanel::user ? 'root' : ( $Cpanel::CPDATA{'OWNER'} || 'root' );

    my $ownerhomedir =
        $cached_real_owner eq 'root'
      ? $Cpanel::ConfigFiles::ROOT_CPANEL_HOMEDIR
      : Cpanel::PwCache::gethomedir($cached_real_owner);

    return ( $cached_contactinfodir = $ownerhomedir . '/cpanelbranding' );
}

sub _getbrandingmtime {
    $_Branding_mtime = 0;
    my $theme            = $Cpanel::CPDATA{'RS'};
    my $brandingdir      = Cpanel::Branding::Lite::Package::_getbrandingdir();
    my $brandingpkg      = Cpanel::Branding::Lite::Package::_getbrandingpkg();
    my $branding_pkg_dir = "/usr/local/cpanel/base/frontend/$theme/branding/$brandingpkg";
    $branding_pkg_dir =~ tr{/}{}s;    # collapse //s to /

    my ( $test_file, $mtime );
    foreach $test_file (
        "$brandingdir/cpanelbranding",
        "$brandingdir/cpanelbranding/timedata",
        '/usr/local/cpanel/cpanel',
        "/usr/local/cpanel/base/frontend/$theme",
        "/usr/local/cpanel/base/frontend/$theme/branding",
        ( $brandingpkg ? $branding_pkg_dir : () )
    ) {
        $mtime = Cpanel::StatCache::cachedmtime($test_file);
        $Cpanel::Debug::level > 5 && print STDERR "Branding::Lite::_getbrandingmtime: $test_file = $mtime\n";
        if ( $mtime && $mtime > $_Branding_mtime ) { $_Branding_mtime = $mtime; }
    }
    return $_Branding_mtime;
}

my $theme_config_cache = {};

# load_theme_config()
# returns back a hash containing the various settings from the config.json file in the themeroot
#
# If this is not run fromt he Cpanel ENV then: appname & teheme name must be provided
# f.ex.: load_theme_config('frontend', 'x3');
sub load_theme_config {
    my $appname = shift || ( ( $Cpanel::appname && $Cpanel::appname eq 'webmail' ) ? 'webmail' : 'frontend' );
    my $theme   = shift || $Cpanel::CPDATA{'RS'} || '';

    # return the theme from memory
    if ( exists $theme_config_cache->{$theme} ) {
        return $theme_config_cache->{$theme};
    }

    # load the file & return the theme
    my $theme_config_file = "/usr/local/cpanel/base/$appname/$theme/config.json";

    my $config = Cpanel::Branding::Lite::Config::load_theme_config_from_file($theme_config_file);

    $theme_config_cache->{$theme} = $config;

    return $config;
}

1;
