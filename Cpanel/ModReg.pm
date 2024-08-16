package Cpanel::ModReg;

# cpanel - Cpanel/ModReg.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel                               ();
use Cpanel::PwCache                      ();
use Cpanel::Branding                     ();
use Cpanel::DynamicUI::Loader            ();
use Cpanel::Branding::Lite               ();
use Cpanel::SpriteGen_ExtPerlMod         ();
use Cpanel::StatCache                    ();
use Cpanel::Config::Users                ();
use Cpanel::AccessIds                    ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::FileUtils::Copy              ();
use Cpanel::StatCache                    ();

our $VERSION = 1.1;

sub CPANEL_USERHOME            { '/var/cpanel/userhomes/cpanel' }
sub DEFAULT_SPRITE_SUBTYPE     { 'img' }
sub DEFAULT_SPRITE_FORMAT      { 'jpg' }
sub DEFAULT_SPRITE_COMPRESSION { 100 }

# pass theme as parameter
sub main_branding_dir { "/usr/local/cpanel/base/frontend/$_[0]/branding" }

sub _get_homedir {
    return $_[0] eq 'cpanel'
      ? CPANEL_USERHOME()
      : ( Cpanel::PwCache::getpwnam( $_[0] ) )[7];
}

#for testing
sub _set_sprite_defaults {
    my $sprite_hr = shift;
    die "No imgtype in sprite: $sprite_hr->{'__string'}\n" if !$sprite_hr->{'imgtype'};

    $sprite_hr->{'subtype'}     ||= DEFAULT_SPRITE_SUBTYPE();
    $sprite_hr->{'format'}      ||= DEFAULT_SPRITE_FORMAT();
    $sprite_hr->{'compression'} ||= DEFAULT_SPRITE_COMPRESSION();
    $sprite_hr->{'filename'} = join(
        '_',
        (
            $sprite_hr->{'imgtype'},
            'sprites',
            $sprite_hr->{'subtype'},
            $sprite_hr->{'method'} || (),
        )
      )
      . '.'
      . $sprite_hr->{'format'};

    return $sprite_hr;
}

sub parse_sprites_string {
    my @sprites;
    foreach my $sprite ( split( m{\|}, $_[0] ) ) {
        my $sprite_hr = {
            __string => $sprite,
            ( map { ( split( /=/, $_ ) )[ 0, 1 ] } ( split( /\,/, $sprite ) ) ),
        };
        _set_sprite_defaults($sprite_hr);

        push @sprites, $sprite_hr;
    }
    return @sprites;
}

sub rebuildsprites {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)
    my ( $theme, $sprites, $force, $verbose, $working_gd, $dist, $cponly ) = @_;

    if ( $dist && !$working_gd ) {
        die "GD must be working in dist mode";
    }
    if ( defined $working_gd && !$working_gd ) {
        print "**** WARNING ****:  GD is broken, we will copy the sprite files from the distribution in place instead of building them *******\n";
    }

    my $mainbrandingdir = main_branding_dir($theme);
    if ( -l $mainbrandingdir ) {
        print "Skipping sprite rebuild for $theme. Branding directory is a symlink.\n";
        return;
    }

    my $now = time();
    print "*** Rebuilding sprites for $theme ***\n";
    local $Cpanel::CPDATA{'RS'} = $theme;

    #1. The default (unnamed) branding. This does not include root's modifications
    #to that branding made as the cpanel user (i.e., from the Branding Editor).
    my @PLIST = (
        {
            'dir'     => $mainbrandingdir,
            'user'    => 'root',
            'homedir' => CPANEL_USERHOME(),
            'pkg'     => '',
        }
    );

    #2. Named brandings, not including Branding Editor modifications.
    if ( -d $mainbrandingdir ) {
        opendir( my $tdir, $mainbrandingdir ) or die "Could not open directory $mainbrandingdir: $!\n";
        while ( my $bpkg = readdir($tdir) ) {
            next if ( $bpkg =~ m/^\./ || !-d $mainbrandingdir . '/' . $bpkg );
            push @PLIST,
              {
                'dir'     => $mainbrandingdir . '/' . $bpkg,
                'user'    => 'root',
                'homedir' => CPANEL_USERHOME(),
                'pkg'     => $bpkg
              };
        }
        closedir($tdir);
    }

    #3. Reseller branding elements. This includes:
    #   * Root's changes to ANY branding, including the default/unnamed branding.
    #   * Resellers' changes to ANY branding.
    #   * Custom brandings uploaded either:
    #       * as a reseller, or
    #       * by root as the cpanel user.
    if ( !$dist && !$cponly ) {
        my @cpusers = Cpanel::Config::Users::getcpusers();
        foreach my $cpuser ( 'cpanel', @cpusers ) {
            next if !Cpanel::isreseller($cpuser);
            my $ownerhomedir = _get_homedir($cpuser);

            my $brandingdir = "$ownerhomedir/cpanelbranding/$theme";
            next if !-d $brandingdir;

            #3.1 Reseller's theme branding dir
            push @PLIST,
              {
                'dir'     => $brandingdir,
                'user'    => $cpuser,
                'homedir' => $ownerhomedir,
                'pkg'     => q{},
              };

            #3.2 Reseller's brandings
            opendir( my $tdir, $brandingdir );
            while ( my $bpkg = readdir($tdir) ) {
                next if ( $bpkg =~ /^\./ );
                next if ( !-d $brandingdir . '/' . $bpkg );
                push @PLIST,
                  {
                    'dir'     => $brandingdir . '/' . $bpkg,
                    'user'    => $cpuser,
                    'homedir' => $ownerhomedir,
                    'pkg'     => $bpkg
                  };
            }
            closedir($tdir);
        }
    }

  CACHE_INIT_LOOP:
    foreach my $brandingtg (@PLIST) {
        my $cache_init_code = sub {

            # Need to set the $Cpanel::homedir for Cpanel::Branding
            local $Cpanel::isreseller = 1;
            local $Cpanel::homedir    = $brandingtg->{'homedir'};
            local $Cpanel::user       = $brandingtg->{'user'};

            Cpanel::DynamicUI::Loader::load_all_dynamicui_confs(
                'theme'        => $theme,
                'ownerhomedir' => $brandingtg->{'homedir'},
                'brandingpkg'  => $brandingtg->{'pkg'},
                'user'         => $brandingtg->{'user'},
                'homedir'      => _get_homedir( $brandingtg->{'user'} ),
            );
        };

        # We fork off a sub-process here because load_all_dynamicui_conf() can allow for possible code execution.
        # We do not want the process to be able to shift back to the root user.

        if ( $brandingtg->{'user'} eq 'root' ) {
            $cache_init_code->();
        }
        else {
            Cpanel::AccessIds::do_as_user(
                $brandingtg->{'user'},
                $cache_init_code,
            );
        }
    }

  BRANDING_LOOP:
    foreach my $brandingtg (@PLIST) {
        my ( $branding_user_uid, $branding_user_gid ) = ( Cpanel::PwCache::getpwnam( $brandingtg->{'user'} ) )[ 2, 3 ];

        my $dynamic_ui_code = sub {

            # Need to set the $Cpanel::homedir for Cpanel::Branding

            local $Cpanel::isreseller = 1;
            local $Cpanel::homedir    = $brandingtg->{'homedir'};
            local $Cpanel::user       = $brandingtg->{'user'};

            my $result = Cpanel::DynamicUI::Loader::load_all_dynamicui_confs(
                'theme'        => $theme,
                'ownerhomedir' => $brandingtg->{'homedir'},
                'brandingpkg'  => $brandingtg->{'pkg'},
                'user'         => $brandingtg->{'user'},
                'homedir'      => _get_homedir( $brandingtg->{'user'} ),
            );

            return $result;
        };

        # We fork off a sub-process here because load_all_dynamicui_conf() can allow for possible code execution.
        # We do not want the process to be able to shift back to the root user.

        my $all_dynamicui_confs;

        if ( $brandingtg->{'user'} eq 'root' ) {
            $all_dynamicui_confs = $dynamic_ui_code->();
        }
        else {
            $all_dynamicui_confs = Cpanel::AccessIds::do_as_user(
                $brandingtg->{'user'},
                $dynamic_ui_code,
            );
        }

        my $branding_update_code = sub {

            # Need to set the $Cpanel::homedir for Cpanel::Branding
            local $Cpanel::isreseller = 1;
            local $Cpanel::homedir    = $brandingtg->{'homedir'};
            local $Cpanel::user       = $brandingtg->{'user'};

            my $brandingpkg = $brandingtg->{'pkg'};
            my $brandingdir = $brandingtg->{'dir'};

            my $dynamicui_cache_creation_time = $all_dynamicui_confs->{'cachetime'};

            while ( $dynamicui_cache_creation_time == time() ) {
                select( undef, undef, undef, 0.1 );
            }    # make sure we don't hit a race

            my $dbrandconf = $all_dynamicui_confs->{'conf'};

            my $branding_has_dist = -d "$brandingdir/.dist";

            if ($branding_has_dist) {
                my $has_sprites = 0;
                foreach my $sprite ( parse_sprites_string($sprites) ) {
                    my $spritefilename = $sprite->{'filename'};
                    my $spritefile     = "$brandingdir/$spritefilename";
                    my $spritedistfile = "$brandingdir/.dist/$spritefilename";
                    if ( -e $spritefile || -e $spritedistfile ) {
                        $has_sprites = 1;
                        last;
                    }
                }
                return if !$has_sprites;
            }

            #print "-=- Skipping Branding Dir: $brandingdir (" . ($brandingpkg ? $brandingpkg : '[root]') . ") [NO DYNAMIC SPRITES] -=-\n";
            print "-=- Processing Branding Dir: $brandingdir (" . ( $brandingpkg ? $brandingpkg : '[root]' ) . ") -=-\n";

            # Remove just in case it has been created improperly in the past
            # reminder for case 10590: update / create the file(s) as user and not root !
            if ( $brandingtg->{'user'} eq 'root' ) {
                Cpanel::AccessIds::ReducedPrivileges::call_as_user( \&reset_timedata, 'cpanel' );
            }
            else {
                reset_timedata();
            }
            Cpanel::Branding::Lite::_clear_memory_cache();

            foreach my $sprite ( parse_sprites_string($sprites) ) {
                my %OPTS           = %$sprite;
                my $method         = $OPTS{'method'};
                my $subtype        = $OPTS{'subtype'};
                my $format         = $OPTS{'format'};
                my $compression    = $OPTS{'compression'};
                my $spritefilename = $OPTS{'filename'};
                my $spritefile     = "$brandingdir/$spritefilename";
                my $spritedistfile = "$brandingdir/.dist/$spritefilename";

                print "\tSprite: $sprite->{'__string'}....";
                my %IMGS;
                my $newest_sprite_mtime = 0;
                my $newest_sprite_img;
                foreach my $file ( sort keys %{$dbrandconf} ) {

                    next if ref $dbrandconf->{$file} ne 'HASH';
                    next if ( !defined( $dbrandconf->{$file}{'type'} ) )    || ( $dbrandconf->{$file}{'type'} ne 'image' );
                    next if ( !defined( $dbrandconf->{$file}{'subtype'} ) ) || ( $dbrandconf->{$file}{'subtype'} ne $subtype );
                    next if ( !defined( $dbrandconf->{$file}{'imgtype'} ) ) || ( $dbrandconf->{$file}{'imgtype'} ne $OPTS{'imgtype'} );

                    $IMGS{$file} = Cpanel::Branding::Branding_image( $file, 1, $brandingpkg, 1 );

                    if ( !$IMGS{$file} ) {
                        delete $IMGS{$file};
                        next;
                    }

                    my $img_mtime = Cpanel::StatCache::cachedmtime( $IMGS{$file} );

                    if ( $img_mtime > $newest_sprite_mtime && $img_mtime < $now ) {
                        print "NEWEST SPRITE IS: $IMGS{$file}\n" if $verbose;
                        $newest_sprite_mtime = $img_mtime;
                        $newest_sprite_img   = $IMGS{$file};
                    }
                    elsif ($verbose) {
                        print "OLDER SPRITE IS $IMGS{$file}: " . $img_mtime . " < $newest_sprite_mtime\n";
                    }
                }

                if ( !%IMGS ) {
                    print "No Images found!\n";
                    next;
                }

                # We are building these on a build server and we want to place them in the .dist subdir
                # so we do not conflict with the ones that will be built on install
                if ($dist) {
                    system( 'git', 'rm', '--force', $spritefile )       if -e $spritefile;
                    system( 'git', 'rm', '--force', "$spritefile.map" ) if -e "$spritefile.map";
                    mkdir( $brandingdir . '/.dist/', 0755 ) if !-e $brandingdir . '/.dist/';
                    $spritefile = $spritedistfile;
                }

                my $spritefile_mtime = ( stat($spritefile) )[9];
                if (  !$force
                    && $newest_sprite_mtime
                    && $spritefile_mtime
                    && $newest_sprite_mtime < $spritefile_mtime
                    && $spritefile_mtime < $now
                    && $spritefile_mtime > $dynamicui_cache_creation_time ) {

                    print "[$spritefile > $newest_sprite_img] [" . localtime($newest_sprite_mtime) . " < " . localtime($spritefile_mtime) . "]\n";
                    print "skipping as there are no new sprites....Done\n";
                    next;
                }

                # Ensure that we'll be able to write this file later.
                for my $f ( $spritefile, $spritefile . '.map' ) {
                    chown( $branding_user_uid, $branding_user_gid, $f ) if -f $f;
                }

                # <do-as-user> sprite (re)generation needed for case 58676
                if ( defined $working_gd && !$working_gd ) {

                    # GD is broken so we need to install these from the .dist dir
                    if ( ( stat($spritefile) )[9] < ( stat($spritedistfile) )[9] ) {
                        print "\tInstalling $spritedistfile into $spritefile\n";
                        Cpanel::FileUtils::Copy::safecopy( $spritedistfile, $spritefile );
                    }
                }
                else {
                    Cpanel::SpriteGen_ExtPerlMod::generate(
                        {
                            'spritemethod'      => $method,
                            'spritetype'        => $subtype,
                            'fileslist'         => \%IMGS,
                            'spritefile'        => $spritefile,
                            'spriteformat'      => $format,
                            'spritecompression' => $compression
                        }
                    );
                }

                # we probably could use only working_gd
                if ( ( !defined $working_gd || $working_gd ) && $dist ) {
                    system( 'git', 'add', "$brandingdir/.dist", $spritefile, "$spritefile.map" );
                }
                print "....Done\n";
            }
        };

        # We only reduce privileges here.
        # The branding code uses all sorts of global variables that don't react well to forks.

        if ( $brandingtg->{'user'} eq 'root' ) {
            $branding_update_code->();
        }
        else {
            Cpanel::AccessIds::ReducedPrivileges::call_as_user(
                $branding_update_code,
                $brandingtg->{'user'},
            );
        }
    }
    print "*** Done rebuilding sprites for $theme ***\n\n\n";
    return;
}

sub loadcfg {
    my ($mfile) = @_;
    my %CFG;
    my $cfgval;
    if ( open my $cpf, '<', $mfile ) {
        while ( my $line = readline($cpf) ) {
            next if $line =~ m/^[\;\#]/;
            next if $line =~ m/^\s*$/;
            $line =~ s/[\015\012]//g;    # Strip Windows and Unix newline chars
            if ( $line =~ m/:/ ) {
                my $cfgdata;
                ( $cfgval, $cfgdata ) = split( /:/, $line, 2 );
                $CFG{$cfgval} = $cfgdata;
            }
            else {
                $CFG{$cfgval} .= "\n" . $line;
            }
        }
        close $cpf;
    }
    else {
        warn "Failed to read $mfile: $!";
    }
    return \%CFG;
}

sub reset_timedata {
    require Cpanel::Branding::Lite::Package;
    Cpanel::Branding::Lite::Package::delete_timedata();
    Cpanel::Branding::Lite::Package::_reset_timedata();
    return;
}

1;
