package Cpanel::Branding::Lite::Package;

# cpanel - Cpanel/Branding/Lite/Package.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Debug        ();
use Cpanel::LoadFile     ();
use Cpanel::Debug        ();
use Cpanel::NVData       ();
use Cpanel::Path::Safety ();
use Cpanel::PwCache      ();
use Cpanel::StatCache    ();
use Cpanel::ConfigFiles  ();

our $ENOENT = 2;

my (
    $first_non_disabled_pkg, $checked_fs_branding_pkg, $fs_branding_pkg,        $cached_owner_homedir,
    $Trueownerhomedir,       $branding_owner,          %BRANDING_DEFAULT_CACHE, %DISABLED_PKG_CACHE,
    $TMPBRANDINGPKG,         $cached_branding_pkg
);

## returns/caches the reseller's homedir or user's owner's homedir
sub _getbrandingdir {
    if ($cached_owner_homedir) { return $cached_owner_homedir; }

    if ( !$branding_owner ) { _checkowner(); }

    my $ownerhomedir;

    if ($Trueownerhomedir) {
        $ownerhomedir = $Trueownerhomedir;
    }
    else {
        $Trueownerhomedir = $ownerhomedir = ( $Cpanel::user && $branding_owner eq $Cpanel::user && $Cpanel::homedir )    # PPI NO PARSE - passed in if needed
          ? $Cpanel::homedir                                                                                             # PPI NO PARSE - passed in if needed
          : Cpanel::PwCache::gethomedir($branding_owner);
    }
    if ( !$ownerhomedir || $branding_owner eq 'root' || $branding_owner eq 'cpanel' ) {
        $ownerhomedir = $Cpanel::cpanelhomedir || Cpanel::PwCache::gethomedir('cpanel');                                 # PPI NO PARSE - passed in if needed
    }
    return ( $cached_owner_homedir = $ownerhomedir );
}

## returns/caches contents of $homedir/.cpanel/nvdata/brandingpkg, or $ownerhomedir/cpanelbranding/$theme/default,
##   or first_non_disabled_pkg; checks for disabled package along the way
sub _getbrandingpkg {
    if    ( defined $TMPBRANDINGPKG )      { return $TMPBRANDINGPKG; }
    elsif ( defined $cached_branding_pkg ) { return $cached_branding_pkg; }

    my $brandingpkg = ( $checked_fs_branding_pkg ? $fs_branding_pkg : _get_nv_brandingpkg() );

    return _getdefaultbrandingpkg() if !defined $brandingpkg;

    if ( _pkgisdisabled( $brandingpkg || '' ) ) {
        my $defpkg = _getdefaultbrandingpkg();
        if ( $brandingpkg eq '' || _pkgisdisabled('') ) {
            return $defpkg if ( $defpkg ne '' && $defpkg ne $brandingpkg && !_pkgisdisabled( $defpkg || '' ) );
            if ( defined $first_non_disabled_pkg ) { return $first_non_disabled_pkg; }
            my $rlist_ref = _showpkgs( 'skiphidden' => 1, 'firstone' => 1, 'noimg' => 1 );
            foreach my $bp (@$rlist_ref) {
                next if ( $bp->{'disabled'} );
                $first_non_disabled_pkg = $bp->{'pkg'};
                return ( $cached_branding_pkg = $bp->{'pkg'} );
            }
        }
        return ( $cached_branding_pkg = $defpkg );
    }

    return ( $cached_branding_pkg = $brandingpkg );
}

## returns/caches $branding_owner is either user or OWNER or root
sub _checkowner {
    return ( $branding_owner = ( ( $Cpanel::isreseller ? $Cpanel::user : $Cpanel::CPDATA{'OWNER'} ) || 'root' ) );    # PPI NO PARSE - passed in if needed
}

## loadfile $ownerhomedir/cpanelbranding/$theme/default
sub _getdefaultbrandingpkg {
    my $theme        = $Cpanel::CPDATA{'RS'} // '';                                                                   # PPI NO PARSE - passed in if needed
    my $ownerhomedir = _getbrandingdir()     // '';
    my $dir          = "$ownerhomedir/cpanelbranding/$theme";

    if ( defined $BRANDING_DEFAULT_CACHE{$dir} ) {
        return $BRANDING_DEFAULT_CACHE{$dir};
    }

    local $!;
    my $pkg = Cpanel::LoadFile::loadfile("$dir/default");
    if ( $! && $! != $ENOENT ) {
        Cpanel::Debug::log_warn("Unable to open $dir/default: $!");
    }

    if ( !defined $pkg ) {
        $pkg = Cpanel::LoadFile::loadfile("$Cpanel::ConfigFiles::ROOT_CPANEL_HOMEDIR/cpanelbranding/$theme/master_default");
    }

    if ( defined $pkg ) {
        chomp $pkg;
    }
    else {
        $pkg = q{};
    }

    _branding_default_cache_store( $dir, $pkg );
    return $pkg;
}

# needed by Cpanel::Branding to update in-memory cache to avoid inconsistency
sub _branding_default_cache_store { return ( $BRANDING_DEFAULT_CACHE{ $_[0] } = $_[1] ) }

## checks $ownerhomedir/cpanelbranding/$theme/$_[0]/disabled
sub _pkgisdisabled {
    if ( exists $DISABLED_PKG_CACHE{ $_[0] } ) {
        return $DISABLED_PKG_CACHE{ $_[0] };
    }
    my $ownerhomedir = _getbrandingdir();
    return ( -e "$ownerhomedir/cpanelbranding/$Cpanel::CPDATA{'RS'}/$_[0]/disabled" )    # PPI NO PARSE - passed in if needed
      ? ( $DISABLED_PKG_CACHE{ $_[0] } = 1 )
      : ( $DISABLED_PKG_CACHE{ $_[0] } = 0 );
}

## returns/caches the package named in the $homedir/.cpanel/nvdata/brandingpkg file
sub _get_nv_brandingpkg {
    $checked_fs_branding_pkg = 1;
    if ( Cpanel::StatCache::cachedmtime( Cpanel::NVData::getnvdir() . '/brandingpkg' ) ) {
        $fs_branding_pkg = Cpanel::NVData::_get('brandingpkg');
        Cpanel::Path::Safety::make_safe_for_path( \$fs_branding_pkg ) if length $fs_branding_pkg;
        return $fs_branding_pkg;
    }
    return;
}

sub _showpkgs {
    my %OPTS = @_;

    my $ownerhomedir = _getbrandingdir();

    #my $brandingpkg  = Cpanel::Branding::Lite::Package::_getbrandingpkg();
    #do not call this here as Cpanel::Branding::Lite::Package::_getbrandingpkg calls us
    my $bc = 0;
    my @RSD;
    my %PLIST;

    my $bbasedir = ( $Cpanel::appname eq 'webmail' ) ? 'webmail' : 'frontend';    # PPI NO PARSE - passed in if needed
    my $theme    = $Cpanel::CPDATA{'RS'};                                         # PPI NO PARSE - passed in if needed

    foreach my $bdir ( "/usr/local/cpanel/base/$bbasedir/$theme/branding", "$ownerhomedir/cpanelbranding/$theme" ) {
        if ( $OPTS{'skipglobal'} eq '1' ) {
            if ( $bc == 0 ) {
                $bc++;
                next;
            }
        }
        if ( opendir my $bd_f, $bdir ) {
            while ( my $dir = readdir($bd_f) ) {
                next if ( $dir =~ /^\./ || !-d "$bdir/$dir" );
                $PLIST{$dir}{$bc} = ( -e "$bdir/$dir/disabled" ? 0 : 1 );
            }
            closedir($bd_f);
        }
        $bc++;
    }

    if ( $OPTS{'showroot'} ) {
        $PLIST{''}{0} = 0;
        if ( -e "$ownerhomedir/cpanelbranding/$theme/disabled" ) {
            $PLIST{''}{1} = 0;
        }
    }

    #PLIST
    #  {brandingpkg}
    #  {sytem = 0, yours = 1} = disabled
    foreach my $dir ( sort { lc $a cmp lc $b } keys %PLIST ) {
        my @TYPES;
        if ( $PLIST{$dir}{0} ) {
            push(
                @TYPES,
                {
                    'type' => 'system',
                    'pkg'  => $dir,
                }
            );
        }

        # did this below to fix typo and  illustrate how much more maintainable BPS code is vs the line above
        if ( defined $PLIST{$dir}{'1'} ) {
            push @TYPES,
              {
                'type' => 'yours',
                'pkg'  => $dir,
              };
        }
        my $disabled = ( defined $PLIST{$dir}{'1'} && $PLIST{$dir}{'1'} == 0 ) ? 1  : 0;
        my $checked  = $disabled                                               ? '' : 'checked';
        next if $OPTS{'skiphidden'}    && $disabled;
        next if $OPTS{'onlyshowyours'} && !defined $PLIST{$dir}{'1'};
        push(
            @RSD,
            {
                'previewimg'   => ( $OPTS{'noimg'} ? q{} : _image( 'preview', 1, $dir ) ),
                'pkgchecked'   => $checked,
                'disabled'     => $disabled,
                'previewsmimg' => ( $OPTS{'noimg'} ? q{} : _image( 'previewsm', 1, $dir ) ),
                'types'        => \@TYPES,
                'selected'     => 1,
                'selectopt'    => 'selected',
                'pkg'          => $dir,
                'pkgname'      => ( length $dir ? $dir : '[root]' ),
            }
        );
        if ( $OPTS{'firstone'} ) { last; }
    }
    return \@RSD;
}

sub _clear_memory_cache {
    Cpanel::StatCache::clearcache();
    ( $cached_branding_pkg, $cached_owner_homedir, $Trueownerhomedir, $branding_owner ) = ( undef, undef, undef, undef );
    return;
}

sub delete_timedata {
    unlink "$Cpanel::homedir/cpanelbranding/timedata";    # PPI NO PARSE - passed in if needed
    return;
}

sub _reset_timedata {
    Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::homedir/cpanelbranding/timedata") if -e "$Cpanel::homedir/cpanelbranding";    # PPI NO PARSE - passed in if needed - invalidate persistent stat cache
    return;
}

sub _clearcache {
    _reset_timedata();
    _clear_memory_cache();
    return;
}

sub _tempsetbrandingpkg {
    return ( $TMPBRANDINGPKG = $_[0] );
}

1;
