package Cpanel::Branding;

# cpanel - Cpanel/Branding.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel                          ();
use Cpanel::Branding::Lite          ();
use Cpanel::Branding::Lite::Package ();
use Cpanel::Branding::Detect        ();
use Cpanel::Encoder::Tiny           ();
use Cpanel::ExtractFile             ();
use Cpanel::FileUtils::Write        ();
use Cpanel::FileUtils::Copy         ();
use Cpanel::FileUtils::TouchFile    ();
use Cpanel::LoadFile                ();
use Cpanel::Locale                  ();
use Cpanel::Logger                  ();
use Cpanel::NVData                  ();
use Cpanel::Path::Safety            ();
use Cpanel::Rand                    ();
use Cpanel::SafeDir::MK             ();
use Cpanel::SafeFile                ();
use Cpanel::SafeRun::Simple         ();
use Cpanel::StatCache               ();
use Cpanel::AdminBin                ();
use Cpanel::DataStore               ();
use Cpanel::DynamicUI::App          ();

use Cpanel::API ();

my $logger = Cpanel::Logger->new();
my $locale;
my $APIref;

# Are we running the optimized version ?
# If we are using Branding 2.1 or later we have to be.
our $VERSION = 4.1;    # Must not end in .0 or the cache may break

sub Branding_init { }
*Branding_text       = *Cpanel::Branding::Lite::_text;
*Branding_file       = *Cpanel::Branding::Lite::_file;
*Branding_image      = *Cpanel::Branding::Lite::_image;
*Branding_clearcache = *Cpanel::Branding::Lite::_clearcache;
*Branding_autodetect = *Cpanel::Branding::Detect::autodetect_mobile_browser;
*_clearcache         = *Cpanel::Branding::Lite::Package::_clearcache;
*_tempsetbrandingpkg = *Cpanel::Branding::Lite::Package::_tempsetbrandingpkg;

## DEPRECATED!
sub Branding_include {
    my ( $file, $skip_default, $raw ) = @_;
    $skip_default = 0 unless $skip_default;
    my $result = Cpanel::API::_execute( "Branding", "include", { file => $file, skip_default => $skip_default, raw => $raw } );
    print $result->data();
    return;
}

sub Branding_contactinclude {
    my ( $file, $raw ) = @_;
    my $include_file = Cpanel::Branding::Lite::_contact_file($file);

    my $branding_dir = Cpanel::Branding::Lite::_get_contactinfodir();

    my $cfg_ref = Cpanel::DataStore::fetch_ref( $branding_dir . '/contactinfo.yaml' ) || {};
    if ( ( $cfg_ref->{'submit_contact_type'} eq 'url' ) && $cfg_ref->{'urlforceredirect'} && $cfg_ref->{'submit_url_input'} ) {
        print '<meta http-equiv="refresh" content="0;url=' . Cpanel::Encoder::Tiny::safe_html_encode_str( $cfg_ref->{'submit_url_input'} ) . '" />';
    }
    else {
        if ($include_file) { main::doinclude( $include_file, ( $raw ? 4 : 0 ), 1 ); }
    }
    return;
}

sub Branding_setupdirs {
    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        $Cpanel::CPERROR{'branding'} = "Sorry, this feature is disabled in demo mode.";
        return $Cpanel::CPERROR{'branding'};
    }
    my $brandingpkg = Cpanel::Branding::Lite::Package::_getbrandingpkg();
    Cpanel::Path::Safety::make_safe_for_path( \$brandingpkg );

    my $theme        = $Cpanel::CPDATA{'RS'};
    my $ownerhomedir = Cpanel::Branding::Lite::Package::_getbrandingdir();

    if ( !-e "$ownerhomedir/cpanelbranding" ) {
        Cpanel::SafeDir::MK::safemkdir( "$ownerhomedir/cpanelbranding", '0755' );
    }
    if ( !-e "$ownerhomedir/cpanelbranding/$theme" ) {
        Cpanel::SafeDir::MK::safemkdir( "$ownerhomedir/cpanelbranding/$theme", '0755' );
    }
    if ( !-e "$ownerhomedir/cpanelbranding/$theme/$brandingpkg" ) {
        Cpanel::SafeDir::MK::safemkdir( "$ownerhomedir/cpanelbranding/$theme/$brandingpkg", '0755' );
    }
    return;
}

sub Branding_killimg {
    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        $Cpanel::CPERROR{'branding'} = "Sorry, this feature is disabled in demo mode.";
        return $Cpanel::CPERROR{'branding'};
    }
    my $imgname     = shift;
    my $theme       = $Cpanel::CPDATA{'RS'};
    my $brandingpkg = Cpanel::Branding::Lite::Package::_getbrandingpkg();

    Cpanel::Path::Safety::make_safe_for_path( \$imgname );
    Cpanel::Path::Safety::make_safe_for_path( \$brandingpkg );

    $imgname =~ s/\.(ico|gif|jpg|png)$//g;

    foreach my $imgtype (@Cpanel::Branding::Lite::EXTLIST) {
        unlink("$Cpanel::homedir/cpanelbranding/$theme/${brandingpkg}/$imgname.$imgtype");
    }

    #touches timedata
    Cpanel::Branding::Lite::Package::_clearcache();
    return;
}

# Deprecated: please use the api2 call
sub Branding_installliveimg {
    if ( $Cpanel::CPDATA{'DEMO'} eq "1" ) {
        $Cpanel::CPERROR{'branding'} = "Sorry, this feature is disabled in demo mode.";
        return $Cpanel::CPERROR{'branding'};
    }
    my $imgname     = shift;
    my $brandingpkg = Cpanel::Branding::Lite::Package::_getbrandingpkg();
    Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::homedir/cpanelbranding/timedata");    #invalidate persistant stat cache

    Cpanel::Path::Safety::make_safe_for_path( \$imgname );
    Cpanel::Path::Safety::make_safe_for_path( \$brandingpkg );

    my $dir = "$Cpanel::homedir/cpanelbranding/" . $Cpanel::CPDATA{'RS'} . '/' . $brandingpkg;
  FILE:
    foreach my $file ( sort keys %Cpanel::FORM ) {
        next FILE if $file =~ m/^file-(.*)-key$/;
        next FILE if $file !~ m/^file-(.*)/;

        my $origfile = $1;
        my @OF       = split( /\./, $origfile );
        my $ext      = $OF[-1];
        rename( $dir . '/' . $origfile, $dir . '/' . $brandingpkg . '/' . $imgname . '.' . $ext );
    }
    return;
}

sub api2_brandingeditor {
    my %OPTS    = @_;
    my $type    = $OPTS{'type'} || 'image';
    my $imgtype = $OPTS{'imgtype'};
    $locale ||= Cpanel::Locale->get_handle();

    if ( defined $OPTS{'brandingpkg'} ) {
        Branding_tempsetbrandingpkg( $OPTS{'brandingpkg'} );
    }
    my @RSD;
    my $dbrandconf = Cpanel::DynamicUI::App::load_dynamic_ui_conf( 'showdeleted' => $OPTS{'showdeleted'}, 'nocache' => 1, 'need_description' => 1, 'need_origin' => 1 );
    my $i;

    my ( $file, $cur_dconf_hr, $cur_dconf_file, $reqext, $description, $url );
    foreach $file ( sort keys %{$dbrandconf} ) {
        $cur_dconf_hr = $$dbrandconf{$file};

        next if $type ne $cur_dconf_hr->{'type'};
        next if $type eq 'image' && $imgtype ne $cur_dconf_hr->{'imgtype'};

        $cur_dconf_file = $cur_dconf_hr->{'file'};

        $reqext = undef;
        if ( $cur_dconf_file =~ /\.(html|jpg|ico|gif|png)$/i ) {
            $reqext = $1;
        }

        $description = $cur_dconf_hr->{'description'} || q{};
        $url =
          $type eq 'image'
          ? Cpanel::Branding::Lite::_image( $cur_dconf_file, 1, undef, 0, 0, 0, 0, 1 )
          : Cpanel::Branding::Lite::_file( $cur_dconf_file, 1 );

        push @RSD,
          {
            number          => ++$i,
            htmldescription => $description || '&nbsp;',
            deleted         => $cur_dconf_hr->{'deleted'} ? 1 : 0,
            url             => $url,
            reqext          => $reqext,
            requiredtxt     => $reqext || $locale->maketext('Requires'),
            description     => $description,
            file            => $cur_dconf_file,
            type            => $type,
            imgtype         => $imgtype,
            global          => $cur_dconf_hr->{'global'},
            group           => $cur_dconf_hr->{'group'},
            height          => $cur_dconf_hr->{'height'},
            origin          => $cur_dconf_hr->{'origin'},
            subtype         => $cur_dconf_hr->{'subtype'},
            width           => $cur_dconf_hr->{'width'},
          };
    }
    if ( $OPTS{'sort'} && $OPTS{'sort'} eq 'group' ) {
        @RSD = sort { $a->{'group'} cmp $b->{'group'} } @RSD;
    }
    return \@RSD;
}

#Runs api2_resolve_file() then substitutes in the appropriate filename if
#none is found.
sub api2_resolvelocalcss {
    my %OPTS = @_;

    my $resolve_result = api2_resolve_file( %OPTS, skipdefault => 1, file => 'local.css' );

    my $ownerhomedir     = Cpanel::Branding::Lite::Package::_getbrandingdir();
    my $is_reseller_file = ( $resolve_result->[0]{'path'} || q{} ) =~ m{\A\Q$ownerhomedir\E};

    if ($is_reseller_file) {
        $resolve_result->[0]{'exists'} = 1;
        if ( $OPTS{'getcss'} ) {
            $resolve_result->[0]{'css'} = Cpanel::LoadFile::loadfile( $resolve_result->[0]{'path'} );
        }
        return $resolve_result;
    }

    #We didn't get an existing file, so send the ideal result now
    my $envtype = Cpanel::Branding::Lite::_loadenvtype();
    my $isvps   = $envtype ne 'standard' ? 1 : 0;

    my $brandingpkg = $OPTS{'brandingpkg'} || $Cpanel::FORM{'brandingpkg'} || Cpanel::Branding::Lite::Package::_getbrandingpkg();
    my $filename    = $isvps ? 'local_vps2.css' : 'local.css';
    my $path        = "$ownerhomedir/cpanelbranding/$Cpanel::CPDATA{'RS'}/$brandingpkg/$filename";

    return [
        {
            file => $filename,
            path => $path,
            ( $OPTS{'getcss'} ? ( css => q{} ) : () ),
            exists => 0,
        }
    ];
}

#Saves local.css in the appropriate path.
sub api2_savelocalcss {
    my %OPTS = @_;

    my $resolve_result = api2_resolvelocalcss( %OPTS, getcss => 0 );

    if ( !$resolve_result->[0]{'exists'} ) {
        $resolve_result->[0]{'path'} =~ m{\A(.*)/[^/]+\z};
        my $dir = $1;
        if ( !Cpanel::SafeDir::MK::safemkdir($dir) ) {
            $Cpanel::CPERROR{'branding'} = "Error creating directory $dir: $!";
            return;
        }
    }

    my $ok = Cpanel::FileUtils::Write::overwrite_no_exceptions( $resolve_result->[0]{'path'}, $OPTS{'css'}, 0644 );

    if ($ok) {
        $resolve_result->[0]{'new'} = !( delete $resolve_result->[0]{'exists'} );
        return $resolve_result;
    }
    else {
        $Cpanel::CPERROR{'branding'} = "Error saving $resolve_result->[0]{'path'}: $!";
        return;
    }
    return;
}

sub api2_resolve_file {
    my %OPTS        = @_;
    my $file        = $OPTS{'file'};
    my $brandingpkg = $OPTS{'brandingpkg'} || $Cpanel::FORM{'brandingpkg'} || Cpanel::Branding::Lite::Package::_getbrandingpkg();
    my $skipdefault = $OPTS{'skipdefault'} ? 1 : 0;
    my $checkmain   = $OPTS{'checkmain'}   ? 1 : 0;

    #  Branding::Lite::_file ( $file, $isvar, $pkg, $inline, $needfile, $skipdefault, $checkmain ) = @_;
    my $file_path = Cpanel::Branding::Lite::_file( $file, 0, $brandingpkg, 0, 1, $skipdefault, $checkmain );
    my $file_name = ( split( /\//, $file_path ) )[-1];

    return [ { 'file' => $file_name, 'path' => $file_path } ];
}

sub api2_getbrandingpkgstatus {
    my %OPTS        = @_;
    my $brandingpkg = $OPTS{'brandingpkg'} || '';
    Cpanel::Path::Safety::make_safe_for_path( \$brandingpkg );

    my @RSD;
    my $dir = "$Cpanel::homedir/cpanelbranding/" . $Cpanel::CPDATA{'RS'} . '/' . $brandingpkg;
    if ( -e $dir . '/disabled' ) {
        push( @RSD, { 'status' => 'disabled', 'nstatus' => 0 } );
    }
    else {
        push( @RSD, { 'status' => 'enabled', 'nstatus' => 1 } );
    }
    return @RSD;
}

sub api2_getdefaultbrandingpkg {
    my $pkg = Cpanel::Branding::Lite::Package::_getdefaultbrandingpkg();
    $pkg ||= '[root]';
    return [ { pkg => $pkg } ];
}

sub Branding_setdefaultbrandingpkg {
    my $pkg          = shift;
    my $allaccounts  = shift;
    my $ownerhomedir = Cpanel::Branding::Lite::Package::_getbrandingdir();
    my $dir          = $ownerhomedir . '/cpanelbranding/' . $Cpanel::CPDATA{'RS'};

    Cpanel::FileUtils::TouchFile::touchfile("$ownerhomedir/cpanelbranding/timedata");    #invalidate persistant stat cache

    if ( open my $default_fh, '>', "$dir/default" ) {
        print {$default_fh} $pkg;
        close $default_fh;
    }
    if ($allaccounts) {
        if ( open my $default_fh, '>', "$dir/master_default" ) {
            print {$default_fh} $pkg;
            close $default_fh;
        }
    }

    # update in-memory cache to match the change we are making, in case getdefaultbrandingpkg gets called
    return Cpanel::Branding::Lite::Package::_branding_default_cache_store( $dir, $pkg );
}

sub api2_setbrandingpkgstatus {
    my %OPTS        = @_;
    my $brandingpkg = Cpanel::Branding::Lite::Package::_getbrandingpkg();
    Cpanel::Path::Safety::make_safe_for_path( \$brandingpkg );

    Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::homedir/cpanelbranding/timedata");    #invalidate persistant stat cache

    my @RSD;
    my $dir = "$Cpanel::homedir/cpanelbranding/" . $Cpanel::CPDATA{'RS'} . '/' . $brandingpkg;
    if ( $OPTS{'action'} eq 'disable' ) {
        Cpanel::FileUtils::TouchFile::touchfile( $dir . '/disabled' );
        push( @RSD, { 'status' => 'disabled' } );
    }
    elsif ( $OPTS{'action'} eq 'enable' ) {
        unlink( $dir . '/disabled' );
        push( @RSD, { 'status' => 'enabled' } );
    }
    return @RSD;
}

sub api2_installimages {
    my @RSD;
    my $brandingpkg = Cpanel::Branding::Lite::Package::_getbrandingpkg();
    my $theme       = $Cpanel::CPDATA{'RS'};
    Cpanel::Path::Safety::make_safe_for_path( \$brandingpkg );

    my $dbrandconf = Cpanel::DynamicUI::App::load_dynamic_ui_conf();
    Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::homedir/cpanelbranding/timedata");    #invalidate persistant stat cache

    my $dir = "$Cpanel::homedir/cpanelbranding/$theme/$brandingpkg";

  IIFILE:
    foreach my $file ( sort keys %Cpanel::FORM ) {
        next IIFILE if $file =~ m/^file-(.*)-key$/;
        next IIFILE if $file !~ m/^file-(.*)/;
        next        if ( $Cpanel::FORM{$file} eq '' );

        my $origfile = $1;
        $origfile =~ m{\.([^\.]+)\z};
        my $ext = lc $1;

        if ( $ext eq 'jpeg' ) { $ext = 'jpg'; }
        my $filekey = $Cpanel::FORM{ 'file-' . $origfile . '-key' };
        $filekey =~ s/^file//g;
        my $imgname = $Cpanel::FORM{ 'filename-' . $filekey };

        next if ( !Cpanel::Path::Safety::safe_in_path($origfile) );
        next if ( !Cpanel::Path::Safety::safe_in_path($imgname) );

        next if !exists $$dbrandconf{$imgname};

        my $targetdir;
        if ( $$dbrandconf{$imgname}{'global'} ) {
            $targetdir = "$Cpanel::homedir/cpanelbranding";
        }
        else {
            $targetdir = "$Cpanel::homedir/cpanelbranding/$theme/$brandingpkg";
        }

        my $target_path = $targetdir;
        $target_path .= '/' . ( $ext eq 'html' ? $imgname : "$imgname.$ext" );
        $target_path =~ tr{/}{}s;    # collapse //s to /

        rename( "$dir/$origfile", $target_path );
        push( @RSD, { 'file' => $origfile, 'destfile' => $target_path } );
    }
    return \@RSD;
}

sub api2_resethtml {
    my %OPTS = @_;
    my @RSD;
    my $brandingpkg = Cpanel::Branding::Lite::Package::_getbrandingpkg();
    my $theme       = $Cpanel::CPDATA{'RS'};

    Cpanel::Path::Safety::make_safe_for_path( \$brandingpkg );
    Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::homedir/cpanelbranding/timedata");    #invalidate persistant stat cache

    my $dbrandconf = Cpanel::DynamicUI::App::load_dynamic_ui_conf();

    foreach my $file ( sort keys %{$dbrandconf} ) {
        Cpanel::Path::Safety::make_safe_for_path( \$file );
        my $cur_dconf_hr = $$dbrandconf{$file};

        next if $cur_dconf_hr->{'type'} ne 'html';
        next if ( exists $OPTS{'file'} && $file ne $OPTS{'file'} );

        if ( $cur_dconf_hr->{'global'} ) {
            unlink("$Cpanel::homedir/cpanelbranding/$file");
        }
        else {
            unlink("$Cpanel::homedir/cpanelbranding/$theme/${brandingpkg}/$file");
        }
        push( @RSD, { file => $file } );
    }

    return \@RSD;
}

sub api2_resetcss {
    my @RSD;
    my $brandingpkg = Cpanel::Branding::Lite::Package::_getbrandingpkg();
    my $theme       = $Cpanel::CPDATA{'RS'};

    Cpanel::Path::Safety::make_safe_for_path( \$brandingpkg );
    Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::homedir/cpanelbranding/timedata");    #invalidate persistant stat cache

    my $dbrandconf = Cpanel::DynamicUI::App::load_dynamic_ui_conf();
    foreach my $file ( sort keys %{$dbrandconf} ) {
        Cpanel::Path::Safety::make_safe_for_path( \$file );
        my $cur_dconf_hr = $$dbrandconf{$file};

        next if $cur_dconf_hr->{'type'} ne 'css';

        unlink("$Cpanel::homedir/cpanelbranding/$theme/${brandingpkg}/$file");

        push( @RSD, { file => $file } );
    }

    return \@RSD;
}

sub api2_cssmerge {
    my %OPTS         = @_;
    my $css          = $OPTS{'css'};
    my $theme        = $Cpanel::CPDATA{'RS'};
    my $brandingpkg  = ( exists $OPTS{'brandingpkg'} ? $OPTS{'brandingpkg'} : Cpanel::Branding::Lite::Package::_getbrandingpkg() );    #case 11014: the blank branding package is '[root]'
    my $ownerhomedir = Cpanel::Branding::Lite::Package::_getbrandingdir();
    Cpanel::FileUtils::TouchFile::touchfile("$ownerhomedir/cpanelbranding/timedata");                                                  #invalidate persistent stat cache

    if ( !-e "$ownerhomedir/cpanelbranding/$theme/${brandingpkg}" ) {
        Cpanel::SafeDir::MK::safemkdir( "$ownerhomedir/cpanelbranding/$theme/${brandingpkg}", 0755 );
    }

    my @CSS_FILE_SEARCH_ORDER = ( 'local_vps2.css', 'local_vps.css', 'local.css' );

    # Calculate the local.css file we are using based on the Branding::Lite::_file call
    # (we are using the api2 call here to make sure we are getting the same one on the page)
    my $current_working_file_ref = api2_resolve_file( 'file' => 'local.css', 'brandingpkg' => $brandingpkg, 'skipdefault' => 1, 'checkmain' => 0 );
    my $file                     = $current_working_file_ref->[0]->{'file'};

    if ( !$file ) {
        $file = Cpanel::Branding::Lite::_loadenvtype() eq 'standard' ? 'local.css' : 'local_vps2.css';
    }

    for ( 0 .. $#CSS_FILE_SEARCH_ORDER ) {
        if ( $CSS_FILE_SEARCH_ORDER[$_] eq $file ) {
            splice( @CSS_FILE_SEARCH_ORDER, 0, $_ );    # remove anything higher in the search order except ourselves
            last;
        }
    }

    my $cssfile = "$ownerhomedir/cpanelbranding/$theme/${brandingpkg}/${file}";
    if ( !-e $cssfile ) {
        my $csslock = Cpanel::SafeFile::safeopen( \*CSSFILE, '>>', $cssfile );
        if ( !$csslock ) {
            $logger->warn("Could not write to $cssfile");
            return;
        }
        foreach my $master_css_file (@CSS_FILE_SEARCH_ORDER) {

            # We try to find the one we are currently updating first,
            # then we fallback to the one the ui is displaying by looking at the search order.
            # We do this in the search order so we are sure we maintain
            # any of the rules that come with the default local*.css
            if ( -e "/usr/local/cpanel/base/frontend/$Cpanel::CPDATA{'RS'}/branding/${brandingpkg}/${master_css_file}" ) {
                Cpanel::FileUtils::Copy::safecopy( "/usr/local/cpanel/base/frontend/$theme/branding/${brandingpkg}/${master_css_file}", $cssfile );
                last;
            }
        }
        Cpanel::SafeFile::safeclose( \*CSSFILE, $csslock );
    }
    my %CSSREG;
    my @CSS = split( /[\r\n]+/, $css );
    foreach my $cssline (@CSS) {

        #STYLE {}
        chomp($cssline);
        my ( $def, $style ) = split( /\{/, $cssline );
        $style =~ s/\}\s*$//g;
        $def   =~ s/^\s*|\s*$//g;
        my @DEF      = split( /\s+/, $def );
        my $cssregex = join( '\s+', @DEF );
        $CSSREG{$cssregex} = { 'def' => $def, 'used' => 0, 'style' => $style };
    }

    Cpanel::FileUtils::TouchFile::touchfile($cssfile);

    if ( !-f $cssfile ) {
        if ( open CSSF, '>>', $cssfile ) {
            close CSSF;
        }
    }
    my $csslock = Cpanel::SafeFile::safeopen( \*CSSFILE, '+<', $cssfile );
    if ( !$csslock ) {
        $logger->warn("Could not edit $cssfile");
        return;
    }
    my @NEWCSS;
    my @FINALCSS;
  CSSFILE:
    while (<CSSFILE>) {
        foreach my $cr ( keys %CSSREG ) {
            if (/$cr\s*\{/) {
                next CSSFILE if ( $CSSREG{$cr}->{'used'} );
                push( @FINALCSS, $CSSREG{$cr}->{'def'} . ' {' . $CSSREG{$cr}->{'style'} . "}\n" );
                $CSSREG{$cr}->{'used'} = 1;
                next CSSFILE;
            }
        }
        push @NEWCSS, $_;
    }
    foreach my $cr ( keys %CSSREG ) {
        if ( !$CSSREG{$cr}->{'used'} ) {
            push( @FINALCSS, $CSSREG{$cr}->{'def'} . ' {' . $CSSREG{$cr}->{'style'} . "}\n" );
        }
    }
    if ( @NEWCSS && $NEWCSS[$#NEWCSS] !~ /[\r\n]+$/ ) {
        $NEWCSS[$#NEWCSS] .= "\n";    #newline
    }
    seek( CSSFILE, 0, 0 );
    print CSSFILE join( '', @NEWCSS, @FINALCSS );
    truncate( CSSFILE, tell(CSSFILE) );
    Cpanel::SafeFile::safeclose( \*CSSFILE, $csslock );

    return [ { 'merge' => 1, 'file' => $file } ];
}

#Does this need to accept ownerhomedir and brandingpkg?
#Case 46951 addresses a case where these were needed in
#Cpanel::ModReg::rebuildsprites.
sub api2_gensprites {    ## no critic qw(Subroutines::RequireArgUnpacking)
    require Cpanel::SpriteGen;
    my %OPTS = @_;
    my @RSD;
    my $dbrandconf  = Cpanel::DynamicUI::App::load_dynamic_ui_conf();
    my $theme       = $Cpanel::CPDATA{'RS'};
    my $brandingpkg = Cpanel::Branding::Lite::Package::_getbrandingpkg();

    my $method      = $OPTS{'method'};
    my $subtype     = defined $OPTS{'subtype'}     ? $OPTS{'subtype'}     : 'img';
    my $format      = defined $OPTS{'format'}      ? $OPTS{'format'}      : 'jpg';
    my $compression = defined $OPTS{'compression'} ? $OPTS{'compression'} : 100;
    my $imgtype     = $OPTS{'imgtype'};

    Cpanel::Path::Safety::make_safe_for_path( \$format );
    Cpanel::Path::Safety::make_safe_for_path( \$OPTS{'imgtype'} );
    my $brandingdir   = "$Cpanel::homedir/cpanelbranding/$theme/${brandingpkg}";
    my $method_part   = $method eq q{} ? q{} : "_$method";
    my $spritefile    = "$brandingdir/${imgtype}_sprites_${subtype}${method_part}.$format";
    my $spritemapfile = "$spritefile.map";

    my %IMGS;
    foreach my $file ( sort keys %{$dbrandconf} ) {
        next if $$dbrandconf{$file}{'type'} ne 'image';
        next if $$dbrandconf{$file}{'subtype'} ne $subtype;
        next if $$dbrandconf{$file}{'imgtype'} ne $OPTS{'imgtype'};
        $IMGS{$file} = Cpanel::Branding::Lite::_image( $file, 1, $brandingpkg, 1 );
    }
    my $res = Cpanel::SpriteGen::generate(
        'spritemethod'      => $method,
        'spritetype'        => $subtype,
        'fileslist'         => \%IMGS,
        'spritefile'        => $spritefile,
        'spriteformat'      => $format,
        'spritecompression' => $compression
    );
    push( @RSD, { 'count' => $res } );

    if ( $INC{'Cpanel/Branding/SpriteMap.pm'} ) {
        delete $Cpanel::Branding::SpriteMap::SPRITEMAPCACHE{$spritemapfile};
    }
    return \@RSD;
}

sub Branding_getapplistorder {

    # This function is marked as private because we do not ever
    # want any other calls to use it.  Its here for legacy reasons
    # only.  Please do not use _get_app_list_order in new code
    print join '|', Cpanel::DynamicUI::App::_get_app_list_order(@_);
    return;
}

sub api2_applist {
    my $applist_ref = Cpanel::DynamicUI::App::get_available_applications();
    return $applist_ref->{'groups'};
}

sub api2_resetall {
    my %OPTS = @_;
    my @RSD;
    my $dbrandconf = Cpanel::DynamicUI::App::load_dynamic_ui_conf();
    foreach my $file ( sort keys %{$dbrandconf} ) {
        if ( $$dbrandconf{$file}{'type'} ne 'image' )             { next; }
        if ( $OPTS{'imgtype'} ne $$dbrandconf{$file}{'imgtype'} ) { next; }
        push( @RSD, { 'file' => $file } );
        Branding_killimg($file);
    }

    return \@RSD;
}

sub api2_killimgs {

    my @RSD;
  IFILE:
    foreach my $file ( sort keys %Cpanel::FORM ) {
        next IFILE if $file =~ m/^file-(.*)-key$/;
        next IFILE if $file !~ m/^file-(.*)/;
        my $origfile = $1;

        next if ( $origfile =~ /^\d+$/ || $Cpanel::FORM{$file} eq '' );

        my @OF = split( /\./, $origfile );

        push( @RSD, { file => join( ".", @OF ) } );

        my $ext     = pop(@OF);
        my $filekey = $Cpanel::FORM{ 'file-' . $origfile . '-key' };
        $filekey =~ s/^file//g;
        my $imgname = $Cpanel::FORM{ 'filename-' . $filekey };

        Branding_killimg($imgname);
    }
    return \@RSD;
}

sub api2_showpkgs {    ## no critic qw(Subroutines::RequireArgUnpacking)
    $locale ||= Cpanel::Locale->get_handle();
    my $pkgref = Cpanel::Branding::Lite::Package::_showpkgs(@_);
    my ( $i, $j, $types_ar );
    for $i ( 0 .. $#$pkgref ) {
        $types_ar = $pkgref->[$i]->{'types'};
        for $j ( 0 .. $#$types_ar ) {

            # API2 does not like _ in key names, so it is not download_link_text
            $types_ar->[$j]{'downloadlinktext'} = $types_ar->[$j]{'type'} eq 'yours' ? $locale->maketext('Download (Yours)') : $locale->maketext('Download (System)');
        }
    }
    return $pkgref;
}

sub Branding_setbrandingpkg {
    Cpanel::StatCache::clearcache();
    Cpanel::NVData::_set( 'brandingpkg', $_[0] );
    return;
}

sub Branding_tempsetbrandingpkg {
    return if !$Cpanel::isreseller;
    goto &Cpanel::Branding::Lite::Package::_tempsetbrandingpkg;
}

sub api2_getbrandingpkg {
    my $brandingpkg = Cpanel::Branding::Lite::Package::_getbrandingpkg();
    my @RSD         = (
        {
            brandingpkg     => $brandingpkg,
            brandingpkgname => ( $brandingpkg eq '' ? '[root]' : $brandingpkg )
        }
    );
    $Cpanel::CPVAR{'brandingpkg'}     = $brandingpkg;
    $Cpanel::CPVAR{'brandingpkgname'} = ( $brandingpkg eq '' ? '[root]' : $brandingpkg );
    return \@RSD;
}

sub api2_delpkg {
    my %OPTS = @_;
    my $pkg  = $OPTS{'pkg'};
    Cpanel::Path::Safety::make_safe_for_path( \$pkg );

    my @RSD;
    if ( $pkg eq '' ) {
        $Cpanel::CPERROR{'branding'} = "You must specify a branding package to add!";
        push( @RSD, { pkg => $pkg, error => $Cpanel::CPERROR{'branding'} } );
        return @RSD;
    }

    my $pkgdir = $Cpanel::homedir . '/cpanelbranding/' . $Cpanel::CPDATA{'RS'} . '/' . $pkg;
    if ( !-d $pkgdir ) {
        $Cpanel::CPERROR{'branding'} = "$pkgdir does not exist!";
        push( @RSD, { pkg => $pkg, error => $Cpanel::CPERROR{'branding'} } );
        return @RSD;
    }

    Cpanel::SafeRun::Simple::saferun( 'rm', '-rf', '--', $pkgdir );

    Cpanel::NVData::_set( 'brandingpkg', '' );

    push( @RSD, { pkg => $pkg } );

    return @RSD;

}

sub api2_installbrandingpkgs {
    Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::homedir/cpanelbranding/timedata");    #invalidate persistant stat cache

    my @RSD;
  PKGFILE:
    foreach my $file ( sort keys %Cpanel::FORM ) {
        next PKGFILE if $file =~ m/^file-(.*)-key$/;
        next PKGFILE if $file !~ m/^file-(.*)/;
        next         if ( $Cpanel::FORM{$file} eq '' );
        my $origfile = $1;
        my @FTREE    = split( m{[\\/]}, $origfile );
        my $fname    = $FTREE[-1];
        $fname =~ tr{/<>;}{}d;    # TODO: same as trunk/ -r 3556 ???

        my $pkgname = $fname;

        #ORDER MATTERS FOR REMOVAL
        $pkgname =~ s/\.tgz$//g;
        $pkgname =~ s/\.gz$//g;
        $pkgname =~ s/\.tar$//g;
        $pkgname =~ s/\.zip$//g;
        $pkgname =~ s/\.cpbranding$//g;
        my $dir;
        if ( $pkgname eq $Cpanel::CPDATA{'RS'} ) {
            $dir = "$Cpanel::homedir/cpanelbranding/" . $Cpanel::CPDATA{'RS'};
        }
        else {
            $dir = "$Cpanel::homedir/cpanelbranding/" . $Cpanel::CPDATA{'RS'} . '/' . $pkgname;
        }

        rename( $dir, $dir . '.previous.' . time() );

        # Extractfile returns the relative path to files when listing
        my $extract_files_ref = Cpanel::ExtractFile::extractfile( $Cpanel::homedir . '/tmp/' . $fname, 'list' => 1 );

      THEMECHECK:
        my $targetdir;

        # Here we find out the actual name of the directory containing the root of the branding package
        # We use this below as the base of the theme
        # $targetdir will be where the actual files are
        # for example:
        # If the tarball is like
        # project/work/happyhost/local.css
        # project/work/happyhost/top.jpg
        # project/work/happyhost/extras/big.jpg
        # then targetdir will be project/work/happyhost
        foreach (@$extract_files_ref) {
            if (/\.\.\//) {
                $Cpanel::CPERROR{'branding'} = "Fatal: Branding package file contains ../";
                return;
            }
            next if (/__MACOSX/);
            if (/\.(?:css|jpg|html|htm|conf|png|jpeg)$/) {
                my @path = split( /\//, $_ );
                pop(@path);
                my $fulldir = join( '/', @path );
                if ( !$targetdir || length($targetdir) > length($fulldir) ) {
                    $targetdir = $fulldir;
                }
            }
        }
        if ( !defined $targetdir ) {
            $Cpanel::CPERROR{'branding'} = "Fatal: The Branding package file did not contain valid branding files.";
            return;
        }

        #this is the temp dir for where we will extract the zip or tar file
        Cpanel::SafeDir::MK::safemkdir( $Cpanel::homedir . '/tmp', '0755' ) if !-e $Cpanel::homedir . '/tmp';

        #extract in "$Cpanel::homedir/cpanelbranding/" . $Cpanel::CPDATA{'RS'} if zip/tar just contains a tarball of the dir
        my $tmp_dir = Cpanel::Rand::get_tmp_dir_by_name( $Cpanel::homedir . '/tmp/branding_install' );    # audit case 46806 ok
        if ( length($tmp_dir) < 10 ) {
            die "Invalid temp dir: $tmp_dir";
        }

        if ( $tmp_dir !~ /\// ) {
            $tmp_dir .= '/';
        }

        # This is the root of the branding package.
        my $extract_root = $tmp_dir . '/' . $targetdir;
        $extract_root =~ s/\/+/\//g;

        #extractfile returns the absolute path to each file when extracting
        my $file_list = Cpanel::ExtractFile::extractfile( $Cpanel::homedir . '/tmp/' . $fname, 'dir' => $tmp_dir );
        my @fl;
        foreach my $fullfile (@$file_list) {
            my $file = $fullfile;
            if ( $file =~ s/^\Q$extract_root\E//g ) {
                $file =~ s/^\/+//g;
                next if ( $file =~ /__MACOSX/ );
                push @fl, { file => $dir . '/' . $file };
            }
        }

        # place the extract root (which we calculated above at the install point which we get the name from the filename)
        rename( $extract_root, $dir );

        chmod( 0755, $dir );
        system 'rm', '-rf', '--', $tmp_dir;
        push(
            @RSD,
            {
                'targetdir' => $targetdir,
                'files'     => \@fl,
                'pkg'       => $pkgname,
                'migrate'   => 0,
            }
        );
        unlink( $Cpanel::homedir . '/tmp/' . $fname );
    }

    return (@RSD);
}

sub api2_createpkg {
    my %OPTS = @_;
    my $pkg  = $OPTS{'pkg'};

    my $error;
    if ( $pkg eq '' ) {
        $error = 'You must specify a branding package to create.';
    }
    elsif ( $pkg eq 'root' ) {
        $error = 'Sorry, "root" is a reserved package name!';
    }
    elsif ( $pkg =~ m{/} ) {
        $error = 'Branding package names may not contain the "/" character.';
    }

    if ($error) {
        $Cpanel::CPERROR{'branding'} = $error;
        return { pkg => $pkg, error => $error };
    }

    my @RSD;

    Cpanel::Path::Safety::make_safe_for_path( \$pkg );
    my $ownerhomedir = Cpanel::Branding::Lite::Package::_getbrandingdir();
    if ( !-d "$ownerhomedir/cpanelbranding/" . $Cpanel::CPDATA{'RS'} . '/' . $pkg ) {
        Cpanel::SafeDir::MK::safemkdir( "$ownerhomedir/cpanelbranding/" . $Cpanel::CPDATA{'RS'} . '/' . $pkg, 0755 );
    }
    my $pkgdir = $Cpanel::homedir . '/cpanelbranding/' . $Cpanel::CPDATA{'RS'} . '/' . $pkg;

    Cpanel::SafeDir::MK::safemkdir($pkgdir);
    if ( !-d $pkgdir ) {
        $Cpanel::CPERROR{'branding'} = "$pkgdir could not be created!";
        push( @RSD, { pkg => $pkg, error => $Cpanel::CPERROR{'branding'} } );
        return @RSD;
    }
    Cpanel::NVData::_set( 'brandingpkg', $pkg );

    push( @RSD, { pkg => $pkg } );

    return @RSD;
}

sub api2_listobjecttypes {
    my $dbrandconf = Cpanel::DynamicUI::App::load_dynamic_ui_conf( 'showdeleted' => 1 );
    my %TYPE_LIST;
    foreach my $file ( sort keys %{$dbrandconf} ) {
        $TYPE_LIST{ $dbrandconf->{$file}{'type'} } = 1;
    }
    my @RSD;
    foreach my $type ( keys %TYPE_LIST ) {
        next if ( !$type || ( $type && $type eq '' ) );
        push @RSD, { type => $type };
    }
    return \@RSD;
}

sub api2_preloadconf {
    Cpanel::DynamicUI::App::load_dynamic_ui_conf( 'showdeleted' => 1 );
    return;
}

sub api2_listimgtypes {
    my $dbrandconf = Cpanel::DynamicUI::App::load_dynamic_ui_conf( 'showdeleted' => 1 );
    my %TYPE_LIST;
    foreach my $file ( sort keys %{$dbrandconf} ) {
        next if ( $dbrandconf->{$file}{'type'} ne 'image' );
        $TYPE_LIST{ $dbrandconf->{$file}{'imgtype'} } = 1;
    }
    my @RSD;
    foreach my $type ( keys %TYPE_LIST ) {
        next if ( !$type || ( $type && $type eq '' ) );
        push @RSD, { imgtype => $type };
    }
    return \@RSD;
}

sub api2_delbrandingobj {
    my %OPTS          = @_;
    my $ownerhomedir  = Cpanel::Branding::Lite::Package::_getbrandingdir();
    my $brandingpkg   = Cpanel::Branding::Lite::Package::_getbrandingpkg();
    my $branding_conf = $ownerhomedir . '/cpanelbranding/' . $Cpanel::CPDATA{'RS'} . '/' . $brandingpkg . '/dynamicui.conf';
    Cpanel::FileUtils::TouchFile::touchfile($branding_conf);
    my $dlock = Cpanel::SafeFile::safeopen( \*DYC, '+<', $branding_conf );
    if ( !$dlock ) {
        $logger->warn("Could not edit $branding_conf");
        return;
    }
    my @DYC;
    my $hasfile = 0;

    while ( readline( \*DYC ) ) {
        chomp();
        next if (/^$/);
        next if (/^\s*#/);
        my @OPTS = split( /\,/, $_ );
        my %DYA;
        foreach my $opt (@OPTS) {
            my ( $name, $value ) = split( /=\>/, $opt );
            $DYA{$name} = $value;
        }
        if ( $DYA{'file'} eq $OPTS{'file'} ) { $hasfile = 1; next(); }
        push @DYC, $_;
    }
    if ( !$OPTS{'undelete'} ) {
        push @DYC, 'file=>' . $OPTS{'file'} . ',skipobj=>1';
    }
    seek( DYC, 0, 0 );
    print DYC join( "\n", @DYC ) . "\n";
    truncate( DYC, tell(DYC) );
    Cpanel::SafeFile::safeclose( \*DYC, $dlock );

    $OPTS{'dynamicui.conf'} = $branding_conf;
    return [ \%OPTS ];
}

sub api2_addbrandingobj {
    my %OPTS          = @_;
    my $ownerhomedir  = Cpanel::Branding::Lite::Package::_getbrandingdir();
    my $brandingpkg   = Cpanel::Branding::Lite::Package::_getbrandingpkg();
    my $branding_conf = $ownerhomedir . '/cpanelbranding/' . $Cpanel::CPDATA{'RS'} . '/' . $brandingpkg . '/dynamicui.conf';
    Cpanel::FileUtils::TouchFile::touchfile($branding_conf);
    if ( !$OPTS{'file'} ) {
        return [ { status => 0, reason => 'File not specified' } ];
    }
    if ( !-e $branding_conf ) {
        $logger->warn("Could not find $branding_conf");
        return;
    }
    my $dlock = Cpanel::SafeFile::safeopen( \*DYC, '+<', $branding_conf );
    if ( !$dlock ) {
        $logger->warn("Could not edit $branding_conf");
        return;
    }
    my @DYC;
    while ( readline( \*DYC ) ) {
        chomp();
        next if (/^$/);
        next if (/^\s*#/);
        my @OPTS = split( /\,/, $_ );
        my %DYA;
        foreach my $opt (@OPTS) {
            my ( $name, $value ) = split( /=\>/, $opt );
            $DYA{$name} = $value;
        }
        if ( $DYA{'file'} eq $OPTS{'file'} ) { next(); }
        push @DYC, $_;
    }
    my @SLIST;
    foreach my $opt ( keys %OPTS ) {
        next if ( !$OPTS{$opt} );
        push @SLIST, "$opt=>$OPTS{$opt}";
    }
    my $slist = join( ',', @SLIST );
    $slist =~ s/\r\n//g;
    seek( DYC, 0, 0 );
    print DYC join( "\n", @DYC ) . "\n";
    print DYC $slist . "\n";
    truncate( DYC, tell(DYC) );
    Cpanel::SafeFile::safeclose( \*DYC, $dlock );
    $OPTS{'status'}         = 1;
    $OPTS{'reason'}         = 'OK';
    $OPTS{'dynamicui.conf'} = $branding_conf;
    return [ \%OPTS ];
}

sub Branding_setmyacctspkg {
    my ( $pkg, $allaccounts ) = @_;
    $pkg         ||= '[root]';
    $allaccounts ||= 0;
    Cpanel::NVData::_set( 'brandingpkg', $pkg );
    Cpanel::AdminBin::adminrun( 'reseller', 'SETBRANDINGPKG', $pkg, $allaccounts, $Cpanel::CPDATA{'RS'} );
    return;
}

my $allow_demo = { allow_demo => 1 };

my $no_demo = {};

my $css_safe_allow_demo = {
    csssafe    => 1,
    allow_demo => 1
};

my $xss_checked_modify_none = {
    xss_checked => 1,
    modify      => 'none',
};

our %API = (
    'addbrandingobj'        => $no_demo,
    'applist'               => $css_safe_allow_demo,
    'listobjecttypes'       => $allow_demo,
    'resethtml'             => $no_demo,
    'brandingeditor'        => $css_safe_allow_demo,
    'getbrandingpkgstatus'  => $allow_demo,
    'preloadconf'           => $allow_demo,
    'cssmerge'              => $xss_checked_modify_none,
    'showpkgs'              => $allow_demo,
    'listimgtypes'          => $allow_demo,
    'resetall'              => $no_demo,
    'killimgs'              => $xss_checked_modify_none,
    'getdefaultbrandingpkg' => $allow_demo,
    'resetcss'              => $no_demo,
    'installbrandingpkgs'   => $no_demo,
    'createpkg'             => $no_demo,
    'getbrandingpkg'        => $allow_demo,
    'delpkg'                => $no_demo,
    'installimages'         => $xss_checked_modify_none,
    'gensprites'            => $no_demo,
    'delbrandingobj'        => $no_demo,
    'setbrandingpkgstatus'  => $no_demo,
    'resolve_file'          => $allow_demo,
    'resolvelocalcss'       => $allow_demo,
    'savelocalcss'          => {
        engine      => 'array',
        modify      => 'none',
        xss_checked => 1,
    },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
