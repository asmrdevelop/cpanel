package Cpanel::LangMods;

# cpanel - Cpanel/LangMods.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache::modules ();
use Cpanel::FindBin                      ();
use Cpanel::Serverinfo::Perl             ();
use Cpanel::PwCache                      ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::SafeRun::API                 ();
use Cpanel::SafeRun::Simple              ();
use Cpanel::SafeRun::Dynamic             ();
use Cpanel::SafeRun::Env                 ();
use Cpanel::SafeRun::Errors              ();
use Cpanel::CachedCommand                ();
use Cpanel::LoadModule                   ();
use Cpanel::Locale                       ();
use Cpanel::Parser::Vars                 ();
use Cpanel::PHPINI                       ();
use Cpanel::Binaries                     ();
use Cpanel::Encoder::URI                 ();
use Cpanel::SV                           ();

use HTML::Entities ();

use Carp;

our $VERSION = '1.6';

# [Function]       [Arguments]    [Returns]
# setup                           Setups up the language so the installer will work
# pre_run                         Should be run right after setup to make sure everything is ok
# getprefix                       Get the dir modules are installed in
# getarchname                     Gets the name of the arch
# list_installed                  Array of Hashes with module data
# list_available                  Array of Hashes with module data
# search           searchstring   Array of Hashes with module data
# uninstall        modulename     Prints raw uninstall info to stdout
# install          modulename     Prints raw install info to stdout
# update           modulename     Prints raw update info to stdout
# update_all                      Updates all installed modules

# These can be changed for pear & pecl installs in an alternate prefix.
our ( $PHP_PREFIX, $pecl, $pear ) = ( '', '', '' );

# PHP Extensions blocked by Apache module
our %BlockedByApache = (
    'eio' => {
        'path' => q{mod_ruid2.so},
        'name' => q{Mod Ruid2},
    },
    'dio' => {
        'path' => q{mod_ruid2.so},
        'name' => q{Mod Ruid2},
    },
);

our $rLANGMODS = {
    'perl' => {
        'name'  => 'Perl Module',
        'names' => 'Perl Module(s)',
        'setup' => sub {
            if ( $> != 0 && !-d $Cpanel::homedir . '/perl' ) {
                mkdir( $Cpanel::homedir . '/perl', 0755 );
            }
            return;
        },
        'magic_status' => sub {
            chdir('/usr/local/cpanel/src/userperl');
            return Cpanel::SafeRun::Simple::saferun("./status");
        },
        'disable_magic' => sub {
            chdir('/usr/local/cpanel/src/userperl');
            Cpanel::SafeRun::API::api_safe_system("./uninstall");
        },
        'enable_magic' => sub {
            print "ERROR: The perl magic is now always installed. In order to use this, users must change their #! to /usr/bin/perlm\n\n";
        },
        'getprefix' => sub {
            if ( $> == 0 ) {
                return Cpanel::Serverinfo::Perl::installsitelib();
            }
            else {
                return $Cpanel::homedir . '/perl';
            }
        },
        'getarchname' => sub {
            return Cpanel::Serverinfo::Perl::archname();
        },
        '_runinstallerdynamic' => sub {
            return Cpanel::SafeRun::Dynamic::saferundynamic( '/usr/local/cpanel/scripts/perlinstaller', @_ );

        },
        '_runinstallerquiet' => sub {
            return Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/perlinstaller', @_ );
        },
        'list_installed' => sub {
            my $self   = shift;
            my $system = shift;
            if ( $system || $> == 0 ) {
                return $self->{'_parsemodlist'}( Cpanel::SafeRun::Env::saferun_r_cleanenv( '/usr/local/cpanel/scripts/perlmods', '-l' ) );
            }
            else {
                return $self->{'_parsemodlist'}( Cpanel::SafeRun::Env::saferun_r_cleanenv( '/usr/local/cpanel/scripts/perlmods', '-l', $Cpanel::homedir . '/perl' ) );
            }
        },
        '_parsemodlist' => sub {
            my @MODLIST;
            my ( $module, $version, $desc );
            my @VERLIST;
            foreach ( split( /\n/, ${ $_[0] } ) ) {
                next if ( ( !m/::/ && !m/=/ ) || m/^Perl=/i );
                ( $module, $version, $desc ) = split( /=/, $_, 3 );
                next if ( !$module || !$version || $version eq 'undef' );
                @VERLIST = ($version);
                push(
                    @MODLIST,
                    {
                        'docurl' => "https://metacpan.org/pod/" . Cpanel::Encoder::URI::uri_encode_str($module),
                        'module' => $module,

                        #'versions' => \@VERLIST,
                        'latest' => $VERLIST[0],
                        'stable' => $VERLIST[0],
                        'info'   => $desc
                    }
                );
            }
            return \@MODLIST;
        },
        'update_all' => sub {
            my $self = shift;
            my @MODS;
            foreach my $mod ( @{ $self->{'list_installed'}($self) } ) {
                push @MODS, $mod->{'module'};
            }
            $self->{'update'}( $self, @MODS );
        },
        'uninstall' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            $mod = mod_cleanup($mod);
            my @cmd = ( '/usr/local/cpanel/scripts/perlmods', '-u', $mod );
            if ( $> == 0 && !$quiet ) {
                Cpanel::SafeRun::Dynamic::saferundynamic(@cmd);
            }
            elsif ( !$quiet ) {
                Cpanel::SafeRun::Dynamic::saferundynamic( @cmd, $Cpanel::homedir . '/perl' );
            }
            elsif ( $> == 0 ) {
                return Cpanel::SafeRun::Errors::saferunallerrors(@cmd);
            }
            else {
                return Cpanel::SafeRun::Errors::saferunallerrors( @cmd, $Cpanel::homedir . '/perl' );
            }

        },
        'install' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            if ( !$quiet ) {
                $self->{'_runinstallerdynamic'}($mod);
            }
            else {
                return $self->{'_runinstallerquiet'}($mod);
            }
        },
        'update' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            if ( !$quiet ) {
                $self->{'install'}( $self, $mod );
            }
            else {
                return $self->{'install'}( $self, $mod, $quiet );
            }
        },
        'list_available' => sub {
            my $self = shift;
            return $self->{'_parsemodlist'}( Cpanel::CachedCommand::cachedmcommand_r_cleanenv( 6000, '/usr/local/cpanel/scripts/perlmods', '-a' ) );
        },
        'search' => sub {
            my $self = shift;
            my $mod  = shift;
            $mod = mod_cleanup($mod);
            if ( $mod eq '.' ) {
                return $self->{'_parsemodlist'}( Cpanel::CachedCommand::cachedmcommand_r_cleanenv( 6000, '/usr/local/cpanel/scripts/perlmods', '-s', $mod ) );
            }
            else {
                return $self->{'_parsemodlist'}( Cpanel::CachedCommand::cachedmcommand_r_cleanenv( 6000, '/usr/local/cpanel/scripts/perlmods', '-s', $mod ) );
            }
        }
    },
    'ruby' => {
        'name'  => 'Ruby Gem',
        'names' => 'Ruby Gem(s)',
        'setup' => sub {
            if ( !-d $Cpanel::homedir . '/ruby' ) {
                mkdir( $Cpanel::homedir . '/ruby', 0755 );
            }
            if ( !-d $Cpanel::homedir . '/ruby/gems' ) {
                mkdir( $Cpanel::homedir . '/ruby/gems', 0755 );
            }
            if ( !-e $Cpanel::homedir . '/.gemrc' ) {
                require Cpanel::RoR::Gems;
                Cpanel::RoR::Gems::write_gemrc($Cpanel::homedir);
            }
        },
        'magic_status' => sub {
            chdir('/usr/local/cpanel/src/userruby');
            return Cpanel::SafeRun::Simple::saferun("./status");
        },
        'disable_magic' => sub {
            chdir('/usr/local/cpanel/src/userruby');
            Cpanel::SafeRun::API::api_safe_system("./uninstall");
        },
        'enable_magic' => sub {
            chdir('/usr/local/cpanel/src/userruby');
            Cpanel::SafeRun::API::api_safe_system("./install");
        },
        'getprefix' => sub {
            if ( $> == 0 ) {
                return '/usr/lib/ruby/gems';
            }
            else {
                return $Cpanel::homedir . '/ruby/gems';
            }
        },
        '_runsysgem' => sub {
            return Cpanel::SafeRun::Env::saferun_r_cleanenv( 'gem', @_ );
        },
        '_rungem' => sub {
            open( STDIN, '<', '/dev/null' );
            if ( $> != 0 ) {
                $ENV{'GEM_HOME'} = $Cpanel::homedir . '/ruby/gems';
            }
            if ( grep( /^--remote$/, @_ ) ) {
                Cpanel::CachedCommand::cachedmcommand_r_cleanenv( 6000, '/usr/local/cpanel/scripts/gemwrapper', '--noexpect', @_ );
            }
            else {
                Cpanel::SafeRun::Env::saferun_r_cleanenv( '/usr/local/cpanel/scripts/gemwrapper', @_ );
            }
        },
        '_rungemdynamic' => sub {
            if ( $> == 0 ) {
                return Cpanel::SafeRun::Dynamic::saferundynamic( '/usr/local/cpanel/scripts/gemwrapper', @_ );
            }
            else {
                $ENV{'GEM_HOME'} = $Cpanel::homedir . '/ruby/gems';
                return Cpanel::SafeRun::Dynamic::saferundynamic( '/usr/local/cpanel/scripts/gemwrapper', @_ );
            }
        },
        '_rungemquiet' => sub {
            if ( $> == 0 ) {
                return Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/gemwrapper', @_ );
            }
            else {
                $ENV{'GEM_HOME'} = $Cpanel::homedir . '/ruby/gems';
                return Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/gemwrapper', @_ );
            }
        },
        'list_installed' => sub {
            my $self = shift;
            my $sys  = shift;
            if ($sys) {
                return $self->{'_parsemodlist'}( $self->{'_runsysgem'}( 'list', '--local' ) );
            }
            return $self->{'_parsemodlist'}( $self->{'_rungem'}( 'list', '--local' ) );
        },
        'update_all' => sub {
            my $self = shift;
            foreach my $mod ( @{ $self->{'list_installed'}($self) } ) {
                next
                  if ( $mod->{'module'} eq 'sources'
                    || $mod->{'module'} =~ m/^rubygems/ );
                $self->{'update'}( $self, $mod->{'module'} );
            }
        },
        'uninstall' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            $mod = mod_cleanup($mod);
            my @cmd = ( 'uninstall', '-I', '-x', '-a', $mod );
            if ( !$quiet ) {
                $self->{'_rungemdynamic'}(@cmd);
            }
            else {
                return $self->{'_rungemquiet'}(@cmd);
            }
        },
        'install' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            $mod = mod_cleanup($mod);
            my @cmd = ( 'install', '-y', $mod );
            if ( !$quiet ) {
                $self->{'_rungemdynamic'}(@cmd);
            }
            else {
                return $self->{'_rungemquiet'}(@cmd);
            }
        },
        'update' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            $mod = mod_cleanup($mod);
            my @cmd = ( 'update', '-y', $mod );
            if ( !$quiet ) {
                $self->{'_rungemdynamic'}(@cmd);
            }
            else {
                return $self->{'_rungemquiet'}(@cmd);
            }
        },
        'list_available' => sub {
            my $self = shift;
            return $self->{'_parsemodlist'}( $self->{'_rungem'}( 'list', '--remote' ) );
        },
        '_parsemodlist' => sub {
            my @MODLIST;
            my $modname;
            my $versions;
            my @VERLIST;
            foreach ( split( /\n/, ${ $_[0] } ) ) {
                next if ( /^\*/ || /^\s*$/ );
                if (m/^\s+/) {
                    next unless @MODLIST;
                    s/^\s+//g;
                    $MODLIST[-1]->{'info'} .= HTML::Entities::decode_entities($_) . ' ';
                }
                elsif (m/^(\S+)\s+\(([^\)]+)/) {
                    $modname  = $1;
                    $versions = $2;
                    @VERLIST  = split( /\,\s*/, $versions );
                    push @MODLIST, {
                        'docurl' => "https://rubygems.org/gems/" . Cpanel::Encoder::URI::uri_encode_str($modname),
                        'module' => $modname,

                        #'versions' => \@VERLIST,
                        'latest' => $VERLIST[0],
                        'stable' => $VERLIST[0]
                    };
                }
            }
            return \@MODLIST;
        },
        'search' => sub {
            my $self = shift;
            my $mod  = shift;
            $mod = mod_cleanup($mod);
            return $self->{'_parsemodlist'}( $self->{'_rungem'}( 'search', '--remote', $mod ) );
        }
    },
    'php-pecl' => {
        'name'  => 'PHP PECL',
        'names' => 'PHP PECL(s)',
        'setup' => sub {
            if ( $> == 0 ) {
                Cpanel::SafeRun::API::api_safe_system('/usr/local/cpanel/bin/patch_Builder_php');
            }
            configure_pear();
        },
        'pre_run' => sub {
            my $self = shift;
            return ${ $self->{'_runpecl'}( 'channel-update', 'pecl.php.net' ) };
        },
        'getprefix' => sub {
            if ( $> == 0 ) {
                return '/usr/local/lib/php';
            }
            else {
                return $Cpanel::homedir . '/php';
            }
        },
        '_runsyspecl' => sub {
            $ENV{'HOME'} = '/';
            local $ENV{'TERM'} = 'dumb';    # Case 68697
            $pecl ||= ( Cpanel::FindBin::findbin( 'pecl', [ "$PHP_PREFIX/bin", "/usr/local/bin" ] ) || 'pecl' );
            return Cpanel::SafeRun::Env::saferun_r_cleanenv( $pecl, @_ );

        },
        '_runpecl' => sub {
            $pecl ||= ( Cpanel::FindBin::findbin( 'pecl', [ "$PHP_PREFIX/bin", "/usr/local/bin" ] ) || 'pecl' );
            my $command_hr = {
                'command'  => [ $pecl, @_ ],
                'cleanenv' => {
                    'http_purge' => 1,
                    'keep'       => [ 'USER', 'HOME', 'TERM' ],
                },
                'return_ref' => 1,
            };

            local $ENV{'TERM'} = 'dumb';    # Case 68697

            if ( $_[0] =~ /list\-/i ) {     #do not cache local lists
                return Cpanel::CachedCommand::cachedmcommand_cleanenv2( 6000, $command_hr );
            }
            else {
                return Cpanel::SafeRun::Env::saferun_cleanenv2($command_hr);
            }
        },
        '_runpecldynamic' => sub {
            $ENV{'TMPDIR'} = ( $Cpanel::homedir || ( Cpanel::PwCache::getpwuid($>) )[7] ) . '/tmp';
            $pecl ||= ( Cpanel::FindBin::findbin( 'pecl', [ "$PHP_PREFIX/bin", "/usr/local/bin" ] ) || 'pecl' );
            my $command_hr = {
                'command'  => [ $pecl, @_ ],
                'cleanenv' => {
                    'http_purge' => 1,
                    'keep'       => [ 'USER', 'HOME', 'TMPDIR', 'TERM' ],
                },
                'errors' => 1,
            };
            local $ENV{'TERM'} = 'dumb';    # Case 68697
            print Cpanel::SafeRun::Env::saferun_cleanenv2($command_hr);
        },
        '_runpeclquiet' => sub {
            $ENV{'TMPDIR'} = ( $Cpanel::homedir || ( Cpanel::PwCache::getpwuid($>) )[7] ) . '/tmp';
            $pecl ||= ( Cpanel::FindBin::findbin( 'pecl', [ "$PHP_PREFIX/bin", "/usr/local/bin" ] ) || 'pecl' );
            my $command_hr = {
                'command'  => [ $pecl, @_ ],
                'cleanenv' => {
                    'http_purge' => 1,
                    'keep'       => [ 'USER', 'HOME', 'TMPDIR', 'TERM' ],
                },
                'errors' => 1,
            };
            local $ENV{'TERM'} = 'dumb';    # Case 68697
            return Cpanel::SafeRun::Env::saferun_cleanenv2($command_hr);
        },

        # Determine if installation allowed
        '_runinstallallowed' => sub {
            my $self   = shift;
            my $mod    = shift;
            my $msgref = shift;
            my $ret;

            # we want to prevent certain extensions from being installed when
            # an Apache module exists (Case 68117)
            my $soref = Cpanel::ConfigFiles::Apache::modules::get_shared_objects();

            if ( exists $BlockedByApache{$mod} && exists $soref->{ $BlockedByApache{$mod}->{'path'} } ) {
                my $locale = Cpanel::Locale->get_handle();
                $$msgref = $locale->maketext( q{Cannot install the [output,acronym,PECL,PHP Extension Community Library] extension “[_1]”.}, $mod );
                $$msgref .= " " . $locale->maketext( q{The [asis,Apache] module “[_1]” is installed.}, $BlockedByApache{$mod}->{'name'} );
                $ret = 0;
            }
            else {
                $ret = 1;
            }

            return $ret;
        },
        'list_installed' => sub {
            my $self = shift;
            my $sys  = shift;
            if ($sys) {
                return $self->{'_decodephplist'}( $self->{'_runsyspecl'}('list') );
            }
            return $self->{'_decodephplist'}( $self->{'_runpecl'}('list') );
        },
        'update_all' => sub {
            my $self    = shift;
            my $oldpath = $ENV{'PATH'};
            $ENV{'PATH'} = "/usr/local/cpanel/scripts/php_sandbox:$ENV{'PATH'}";
            $self->{'_runpecldynamic'}('upgrade-all');
            $ENV{'PATH'} = $oldpath;
        },
        'update' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            $mod = mod_cleanup($mod);

            $quiet ||= 0;

            # determine if we can install this extension
            my $msg;
            if ( defined $self->{'_runinstallallowed'} && !$self->{'_runinstallallowed'}( $self, $mod, \$msg ) ) {
                print "$msg\n" unless $quiet;
                return ( $quiet ? $msg : 0 );    # return 0 to maintain same return value if it was allowed
            }

            my $oldpath = $ENV{'PATH'};
            $ENV{'PATH'} = "/usr/local/cpanel/scripts/php_sandbox:$ENV{'PATH'}";
            my $output;
            if ( !$quiet ) {
                $self->{'_runpecldynamic'}( 'upgrade', $mod );
            }
            else {
                $output = $self->{'_runpeclquiet'}( 'upgrade', $mod );
            }
            if ( $> == 0 ) {
                my ( $ok, $res ) = Cpanel::PHPINI::install_extension( $mod . '.so', $PHP_PREFIX );
                my $tidy;
                {
                    local $ENV{'PATH'} = $oldpath;
                    $tidy = Cpanel::SafeRun::Simple::saferun('/usr/local/cpanel/scripts/phpini_tidy');
                }
                if ( !$quiet ) {
                    print $res . "\n" . $tidy;
                }
                else {
                    $output .= $res . "\n" . $tidy;
                }
            }
            $ENV{'PATH'} = $oldpath;
            return $output if $quiet;
        },
        'list_updateable' => sub {
            my $self = shift;
            return $self->{'_decodephplist'}( $self->{'_runpecl'}('list-upgrades') );
        },
        'package_info' => sub {
            my $self = shift;
            my $mod  = shift;
            $mod = mod_cleanup($mod);
            return $self->{'_runpecl'}( 'remote-info', $mod );
        },
        'search' => sub {
            my $self = shift;
            my $mod  = shift;
            $mod = mod_cleanup($mod);
            return $self->{'_decodephplist'}( $self->{'_runpecl'}( 'search', $mod ) );
        },
        'list_available' => sub {
            my $self = shift;
            return $self->{'_decodephplist'}( $self->{'_runpecl'}('list-all') );
        },
        'uninstall' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            $mod = mod_cleanup($mod);
            my $oldpath = $ENV{'PATH'};
            $ENV{'PATH'} = "/usr/local/cpanel/scripts/php_sandbox:$ENV{'PATH'}";
            my $output;
            if ( !$quiet ) {
                $self->{'_runpecldynamic'}( 'uninstall', $mod );
            }
            else {
                $output = $self->{'_runpeclquiet'}( 'uninstall', $mod );
            }
            if ( $> == 0 ) {
                my ( $ok, $res ) = Cpanel::PHPINI::uninstall_extension( $mod . '.so', $PHP_PREFIX );
                if ( !$quiet ) {
                    print $res;
                }
                else {
                    $output .= $res;
                }
            }
            $ENV{'PATH'} = $oldpath;
            return $output if $quiet;
        },
        'install' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            my $msg;
            $mod = mod_cleanup($mod);

            $quiet ||= 0;

            # determine if we can install this extension
            if ( defined $self->{'_runinstallallowed'} && !$self->{'_runinstallallowed'}( $self, $mod, \$msg ) ) {
                print "$msg\n" unless $quiet;
                return ( $quiet ? $msg : 0 );    # return 0 to maintain same return value if it was allowed
            }

            my $oldpath = $ENV{'PATH'};
            $ENV{'PATH'} = "/usr/local/cpanel/scripts/php_sandbox:$ENV{'PATH'}";
            my $output;
            if ( !$quiet ) {
                $self->{'_runpecldynamic'}( 'install', $mod );
            }
            else {
                $output = $self->{'_runpeclquiet'}( 'install', $mod );
            }
            if ( $> == 0 ) {
                my ( $ok, $res ) = Cpanel::PHPINI::install_extension( $mod . '.so', $PHP_PREFIX );
                my $tidy;
                {
                    local $ENV{'PATH'} = $oldpath;
                    $tidy = Cpanel::SafeRun::Simple::saferun('/usr/local/cpanel/scripts/phpini_tidy');
                }
                if ( !$quiet ) {
                    print $res . "\n" . $tidy;
                }
                else {
                    $output .= $res . "\n" . $tidy;
                }
            }
            $ENV{'PATH'} = $oldpath;
            return $output if $quiet;
        },
        '_decodephplist' => sub {
            my $inml = 0;
            my @MODLIST;
            my ( @VLIST, @VERSIONLIST, $module, $vi, $info, $latest, $stable, $installed );
            foreach ( split( /\n/, ${ $_[0] } ) ) {
                if ($inml) {
                    chomp();
                    if (/^\s+/) {
                        if (@MODLIST) {
                            my $extra_info = $_;
                            $extra_info =~ s/^\s+//;
                            $MODLIST[$#MODLIST]->{'info'} .= " " . $extra_info;
                        }
                        next;
                    }
                    next if (m{^\s*(<br />|<b>)});

                    ( $module, $vi ) = split( /\s+/, $_, 2 );
                    $module =~ s/^pecl\///g;

                    my @parse_block = split( /(\s+)/, $vi );
                    while ( @parse_block && $parse_block[0] =~ m/^[\(0-9]/ ) {
                        my $version = shift(@parse_block);
                        $version =~ s/[()]//g;
                        if ( $version =~ m{/} ) {
                            my @VERSIONS = split( m{/}, $version );
                            push @VLIST, pop(@VERSIONS);
                            push @VLIST, join( '/', @VERSIONS ) if @VERSIONS;
                        }
                        else {
                            push @VLIST, $version;
                        }
                        shift(@parse_block) if $parse_block[0] =~ m/^\s*$/;
                    }
                    $info = join( '', @parse_block );
                    next unless $info;
                    $latest      = shift(@VLIST);
                    $installed   = $stable = shift(@VLIST);
                    @VERSIONLIST = ();
                    if ($stable)    { push @VERSIONLIST, $stable; }
                    if ($latest)    { push @VERSIONLIST, $latest; }
                    if ( !$stable ) { $stable = $latest; }
                    $module =~ s/^pear\///g;
                    next if ( !$module || $module eq '' );
                    push @MODLIST, {
                        'docurl' => "http://pecl.php.net/package/" . Cpanel::Encoder::URI::uri_encode_str($module),
                        'module' => $module,
                        'latest' => $latest,

                        #'versions' => \@VERSIONLIST,
                        'stable'    => $stable,
                        'installed' => $installed,
                        'info'      => $info
                    };
                }
                if ( !/\s+Package/i && /Package\s+/i ) {
                    $inml = 1;
                }
            }
            return \@MODLIST;
        }
    },
    'php-pear' => {
        'name'  => 'PHP Extensions and Applications Package',
        'names' => 'PHP Extension(s) and Application(s)',
        'setup' => sub {
            configure_pear(1);
        },
        'magic_status' => sub {
            chdir('/usr/local/cpanel/src/userphp');
            return Cpanel::SafeRun::Simple::saferun("./status");
        },
        'disable_magic' => sub {
            chdir('/usr/local/cpanel/src/userphp');
            Cpanel::SafeRun::API::api_safe_system("./uninstall");
        },
        'enable_magic' => sub {
            chdir('/usr/local/cpanel/src/userphp');
            Cpanel::SafeRun::API::api_safe_system("./install");
        },
        'pre_run' => sub {
            my $self = shift;
            return ${ $self->{'_runpear'}( 'channel-update', 'pear.php.net' ) };
        },
        'getprefix' => sub {
            if ( $> == 0 ) {
                return '/usr/local/lib/php';
            }
            else {
                return $Cpanel::homedir . '/php';
            }
        },
        '_runsyspear' => sub {
            $ENV{'HOME'} = '/';
            $pear ||= ( Cpanel::FindBin::findbin( 'pear', [ "$PHP_PREFIX/bin", "/usr/local/bin" ] ) || 'pear' );
            return Cpanel::SafeRun::Env::saferun_r_cleanenv( $pear, @_ );
        },
        '_runpear' => sub {
            $pear ||= ( Cpanel::FindBin::findbin( 'pear', [ "$PHP_PREFIX/bin", "/usr/local/bin" ] ) || 'pear' );
            my $command_hr = {
                'command'  => [ $pear, @_ ],
                'cleanenv' => {
                    'http_purge' => 1,
                    'keep'       => [ 'USER', 'HOME' ],
                },
                'return_ref' => 1,
            };

            if ( $_[0] =~ /list\-/i ) {    #do not cache local lists
                return Cpanel::CachedCommand::cachedmcommand_cleanenv2( 6000, $command_hr );
            }
            else {
                return Cpanel::SafeRun::Env::saferun_cleanenv2($command_hr);
            }
        },
        '_runaltpear' => sub {
            my $ver = shift;
            my $cmd = shift;
            $pear ||= ( Cpanel::FindBin::findbin( 'pear', ["/opt/alt/php$ver/usr/bin"] ) || 'pear' );
            my $command_hr = {
                'command'  => [ $pear, '-c', "/opt/alt/php$ver/etc/pear.conf", $cmd, @_ ],
                'cleanenv' => {
                    'http_purge' => 1,
                    'keep'       => [ 'USER', 'HOME' ],
                },
                'return_ref' => 1,
            };

            if ( $cmd =~ /list\-/i ) {    #do not cache local lists
                return Cpanel::CachedCommand::cachedmcommand_cleanenv2( 6000, $command_hr );
            }
            else {
                return Cpanel::SafeRun::Env::saferun_cleanenv2($command_hr);
            }
        },
        '_altpear_get_channels' => sub {
            my $self = shift;
            my @channels;
            my $output_sr = $self->{'_runaltpear'}( '', 'list-channels' );
            return unless ref $output_sr eq 'SCALAR';

            my @list = split( /\n/, $$output_sr );
            foreach my $line ( @list[ 3 .. $#list ] ) {
                my @row = split /\s+/, $line;
                push @channels, $row[1] if $#row > 1;
            }
            return @channels;

        },
        '_runpeardynamic' => sub {
            $pear ||= ( Cpanel::FindBin::findbin( 'pear', [ "$PHP_PREFIX/bin", "/usr/local/bin" ] ) || 'pear' );
            my $command_hr = {
                'command'  => [ $pear, @_ ],
                'cleanenv' => {
                    'http_purge' => 1,
                    'keep'       => [ 'USER', 'HOME' ],
                },
                'errors' => 1,
            };
            return Cpanel::SafeRun::Env::saferun_cleanenv2($command_hr);
        },
        'list_installed' => sub {
            my ( $self, $sys )     = @_;
            my ( $type, $version ) = _get_php_type_version();

            return $self->{'_decodephplist'}( $self->{'_runpear'}('list') ) unless $sys;

            my $syspear = $self->{'_decodephplist'}( $self->{'_runsyspear'}('list') );
            return $syspear unless $type && $type eq 'alt';

            my @modules = @$syspear;
            foreach my $channel ( $self->{'_altpear_get_channels'}($self) ) {
                my $mod = $self->{'_decodephplist'}( $self->{'_runaltpear'}( $version, 'list', '-c', $channel ) );
                push @modules, @$mod;
            }
            return \@modules;
        },
        'update_all' => sub {
            my $self    = shift;
            my $oldpath = $ENV{'PATH'};
            $ENV{'PATH'} = "/usr/local/cpanel/scripts/php_sandbox:$ENV{'PATH'}";
            print $self->{'_runpeardynamic'}('upgrade-all');
            $ENV{'PATH'} = $oldpath;
        },
        'update' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            $mod = mod_cleanup($mod);
            my $oldpath = $ENV{'PATH'};
            $ENV{'PATH'} = "/usr/local/cpanel/scripts/php_sandbox:$ENV{'PATH'}";
            my $output = $self->{'_runpeardynamic'}( 'upgrade', '-a', $mod );
            $ENV{'PATH'} = $oldpath;

            if ( !$quiet ) {
                print $output;
            }
            else {
                return $output;
            }
        },
        'list_updateable' => sub {
            my $self = shift;
            return $self->{'_decodephplist'}( $self->{'_runpear'}('list-upgrades') );
        },
        'search' => sub {
            my $self = shift;
            my $mod  = shift;
            $mod = mod_cleanup($mod);
            return $self->{'_decodephplist'}( $self->{'_runpear'}( 'search', $mod ) );
        },
        'list_available' => sub {
            my $self = shift;
            return $self->{'_decodephplist'}( $self->{'_runpear'}('list-all') );
        },
        'uninstall' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            my $opts  = shift || [];
            $mod = mod_cleanup($mod);
            my $oldpath = $ENV{'PATH'};
            $ENV{'PATH'} = "/usr/local/cpanel/scripts/php_sandbox:$ENV{'PATH'}";
            my $output = $self->{'_runpeardynamic'}( 'uninstall', @$opts, $mod );
            $ENV{'PATH'} = $oldpath;

            if ( !$quiet ) {
                print $output;
            }
            else {
                return $output;
            }
        },
        'install' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            $mod = mod_cleanup($mod);
            my $oldpath = $ENV{'PATH'};
            $ENV{'PATH'} = "/usr/local/cpanel/scripts/php_sandbox:$ENV{'PATH'}";
            my $output = $self->{'_runpeardynamic'}( 'install', '-a', $mod );

            if ( $output =~ m/Failed\s+to\s+download/ && $output =~ m/use\s+"channel:\/\/pear\.php\.net\/([^"]+)/ ) {    # only interested in first occurrence
                $output = $self->{'_runpeardynamic'}( 'install', '-a', $1 );
                print $output if !$quiet;
            }
            else {
                print $output if !$quiet;
            }
            $ENV{'PATH'} = $oldpath;
            return $output if $quiet;
        },
        'reinstall' => sub {
            my $self  = shift;
            my $mod   = shift;
            my $quiet = shift;
            doaction( 'php-pear', 'uninstall', $mod, $quiet, ['-n'] );
            doaction( 'php-pear', 'install', $mod, $quiet );
        },
        '_decodephplist' => sub {
            my $inml = 0;
            my @MODLIST;
            my ( @VERSIONLIST, $module, $vi, @VLIST, $info, $latest, $stable, $installed );
            foreach ( split( /\n/, ${ $_[0] } ) ) {
                if ($inml) {
                    chomp();
                    if (/^\s+/) {
                        if (@MODLIST) {
                            my $extra_info = $_;
                            $extra_info =~ s/^\s+//;
                            $MODLIST[$#MODLIST]->{'info'} .= " " . $extra_info;
                        }
                        next;
                    }
                    next if (m{^\s*(<br />|<b>)});

                    ( $module, $vi ) = split( /\s+/, $_, 2 );
                    $module =~ s/^pear\///g;
                    my @parse_block = split( /(\s+)/, $vi );
                    while ( @parse_block && $parse_block[0] =~ m/^[\(0-9]/ ) {
                        my $version = shift(@parse_block);
                        $version =~ s/[()]//g;
                        if ( $version =~ m{/} ) {
                            my @VERSIONS = split( m{/}, $version );
                            push @VLIST, pop(@VERSIONS);
                            push @VLIST, join( '/', @VERSIONS ) if @VERSIONS;
                        }
                        else {
                            push @VLIST, $version;
                        }
                        shift(@parse_block) if $parse_block[0] =~ m/^\s*$/;
                    }
                    $info = join( '', @parse_block );
                    next unless $info;
                    $latest      = shift(@VLIST);
                    $installed   = $stable = shift(@VLIST);
                    @VERSIONLIST = ();
                    if ($stable)    { push @VERSIONLIST, $stable; }
                    if ($latest)    { push @VERSIONLIST, $latest; }
                    if ( !$stable ) { $stable = $latest; }
                    $module =~ s/^pear\///g;
                    next if ( !$module || $module eq '' );
                    push @MODLIST, {
                        'docurl' => "http://pear.php.net/package/" . Cpanel::Encoder::URI::uri_encode_str($module) . "/docs",
                        'module' => $module,
                        'latest' => $latest,

                        #'versions' => \@VERSIONLIST,
                        'stable'    => $stable,
                        'installed' => $installed,
                        'info'      => $info
                    };
                }
                if ( !/\s+Package/i && /Package/i ) {
                    $inml = 1;
                }
            }
            return \@MODLIST;
        }
    }
};

sub LangMods_init { 1; }

sub langlist {
    my @LIST;
    foreach my $lang ( keys %{$rLANGMODS} ) {
        push @LIST, $lang;
    }
    return @LIST;
}

sub hasaction {
    my $lang   = shift;
    my $action = shift;
    return 1 if ref $rLANGMODS->{$lang}->{$action} eq 'CODE';
    return 0;
}

sub doaction {
    my $lang   = shift;
    my $action = shift;

    if ( !length $lang ) {
        return ( 0, 'Provide a language.' );
    }
    elsif ( !length $action ) {

        # NOTE: If this block is entered, this function was not called correctly.
        # Therefore, exit abnormally, and direct whoever reads it to report it.

        confess "No action was provided. Report this as a defect.";
    }
    elsif ( ref $rLANGMODS->{$lang}->{$action} eq 'CODE' ) {
        Cpanel::LoadModule::load_perl_module('Cwd') if !$INC{'Cwd.pm'};
        my $cwd = Cwd::fastcwd();
        $ENV{'HOME'} = $Cpanel::homedir || ( Cpanel::PwCache::getpwuid($>) )[7];
        $ENV{'USER'} = $Cpanel::user    || ( Cpanel::PwCache::getpwuid($>) )[0];
        my $rref = &{ $rLANGMODS->{$lang}->{$action} }( $rLANGMODS->{$lang}, @_ );
        chdir $cwd;
        return ( 1, $rref );
    }
    else {
        return ( 0, "Sorry $lang does not support the action $action" );
    }
}

sub _getnewesttarballver {
    my $dir      = shift;
    my $name     = shift;
    my $maxmajor = 0;
    my $maxminor = 0;
    my $maxrev   = 0;

    if ( opendir my $tarball_dh, $dir ) {
        while ( my $file = readdir $tarball_dh ) {
            if ( $file =~ m/^($name-[^"]+)/ ) {
                my $filename = $1;
                next if $filename !~ m/\.(?:gz|bz2|tgz)$/;
                my $version = $filename;
                $version =~ s/^$name-//g;
                $version =~ s/\.tar\.gz$//g;
                my ( $major, $minor, $rev ) = split( /\./, $version );

                if ( $maxmajor < $major ) {
                    $maxmajor = $major;
                    $maxminor = $minor;
                    $maxrev   = $rev;
                }
                elsif ( $maxminor < $minor ) {
                    $maxminor = $minor;
                    $maxrev   = $rev;
                }
                elsif ( $maxrev < $rev ) {
                    $maxrev = $rev;
                }
            }
        }
        closedir $tarball_dh;
    }
    return $maxmajor . '.' . $maxminor . '.' . $maxrev;
}

sub api2_getprefix {
    my %OPTS = @_;
    my $lang = $OPTS{'lang'};
    my ( $ok, $result ) = Cpanel::LangMods::doaction( $lang, 'getprefix' );
    my @RSD = ( { status => $ok, prefix => $result } );
    return \@RSD;
}

sub api2_getarchname {
    my %OPTS = @_;
    my $lang = $OPTS{'lang'};
    my ( $ok, $result ) = Cpanel::LangMods::doaction( $lang, 'getarchname' );
    my @RSD = ( { status => $ok, archname => $result } );
    return \@RSD;
}

sub api2_getkey {
    my %OPTS = @_;
    my $lang = $OPTS{'lang'};
    my $key  = $OPTS{'key'};
    my @RSD  = ( { key => $rLANGMODS->{$lang}->{$key} } );
    return \@RSD;
}

sub api2_setup {
    my %OPTS = @_;
    my $lang = $OPTS{'lang'};
    my ( $ok, $result ) = Cpanel::LangMods::doaction( $lang, 'setup' );
    my @RSD = ( { status => $ok, result => $result } );
    return \@RSD;
}

sub api2_magic_status {
    my %OPTS = @_;
    my $lang = $OPTS{'lang'};
    my ( $ok, $result ) = Cpanel::LangMods::doaction( $lang, 'magic_status' );
    $Cpanel::CPVAR{'magic_status'} = $result;
    return $result;
}

sub api2_list_installed {
    my %OPTS = @_;
    my $lang = $OPTS{'lang'};
    my $sys  = $OPTS{'sys'} || 0;
    my ( $ok, $result ) = Cpanel::LangMods::doaction( $lang, 'list_installed', $sys );
    return $result;
}

sub _search_backend {
    my %OPTS   = @_;
    my $want   = int( $OPTS{'want'} || 100 );
    my $skip   = int( $OPTS{'skip'} || 0 );
    my $lang   = $OPTS{'lang'};
    my $action = $OPTS{'action'};
    my $regex  = $OPTS{'regex'};

    my ( $ok, $result );
    if ( $action eq 'list_available' ) {
        ( $ok, $result ) = Cpanel::LangMods::doaction( $lang, 'list_available' );
    }
    else {
        ( $ok, $result ) = Cpanel::LangMods::doaction( $lang, 'search', $regex );
    }

    if ( $ok && ref($result) eq 'ARRAY' ) {
        my $numhits = $#{$result} + 1;
        my $startpt = ( $want * $skip );
        if ( $startpt > $numhits ) {
            $startpt = ( $numhits - $want );
        }
        my $currentpage = int( $skip + 1 );
        my $pages       = int( $numhits / $want );
        $Cpanel::CPVAR{'wantnext'}     = ( $skip + 1 );
        $Cpanel::CPVAR{'wantprev'}     = ( $skip - 1 );
        $Cpanel::CPVAR{'currentpage'}  = $currentpage;
        $Cpanel::CPVAR{'pages'}        = $pages;
        $Cpanel::CPVAR{'itemsperpage'} = $want;
        if ( $Cpanel::CPVAR{'wantprev'} < 0 )      { $Cpanel::CPVAR{'wantprev'} = 0; }
        if ( $Cpanel::CPVAR{'wantnext'} > $pages ) { $Cpanel::CPVAR{'wantprev'} = $pages; }

        splice( @{$result}, 0, $startpt );
        splice( @{$result}, $want );
    }
    elsif ( !$ok && !length( ref($result) ) ) {
        $Cpanel::CPERROR{$Cpanel::context} = $result;
    }

    return $result;
}

sub api2_search {
    _search_backend( @_, 'action' => 'search' );
}

sub api2_list_available {
    _search_backend( @_, 'action' => 'list_available' );
}

sub api2_pre_run {
    my %OPTS = @_;
    my $lang = $OPTS{'lang'};
    my @RSD;
    if ( Cpanel::LangMods::hasaction( $lang, 'pre_run' ) ) {
        my ( $ok, $result ) = Cpanel::LangMods::doaction( $lang, 'pre_run' );
        @RSD = ( { status => $ok, result => $result } );
    }
    return \@RSD;
}

sub api2_update {
    my %OPTS  = @_;
    my $lang  = $OPTS{'lang'};
    my $mod   = $OPTS{'mod'};
    my $quiet = $Cpanel::Parser::Vars::altmode;
    if ( defined( $OPTS{'quiet'} ) ) {
        $quiet = $OPTS{'quiet'};
    }
    my ( $ok, $result ) = Cpanel::LangMods::doaction( $lang, 'update', $mod, $quiet );
    return { status => $ok, result => $result };
}

sub api2_uninstall {
    my %OPTS  = @_;
    my $lang  = $OPTS{'lang'};
    my $mod   = $OPTS{'mod'};
    my $quiet = $Cpanel::Parser::Vars::altmode;
    if ( defined( $OPTS{'quiet'} ) ) {
        $quiet = $OPTS{'quiet'};
    }
    my ( $ok, $result ) = Cpanel::LangMods::doaction( $lang, 'uninstall', $mod, $quiet );
    return { 'status' => $ok, 'result' => $result };
}

sub api2_install {
    my %OPTS  = @_;
    my $lang  = $OPTS{'lang'};
    my $mod   = $OPTS{'mod'};
    my $quiet = $Cpanel::Parser::Vars::altmode;
    if ( defined( $OPTS{'quiet'} ) ) {
        $quiet = $OPTS{'quiet'};
    }
    my ( $ok, $result ) = Cpanel::LangMods::doaction( $lang, 'install', $mod, $quiet );
    return { status => $ok, result => $result };
}

sub api2_langlist {
    my @LIST;
    foreach my $lang ( keys %{$rLANGMODS} ) {
        push @LIST, { lang => $lang, name => $rLANGMODS->{$lang}->{name} };
    }
    return \@LIST;
}

sub configure_pear {
    my ( $quiet, @pear_args ) = @_;

    my $homedir = $Cpanel::homedir || ( Cpanel::PwCache::getpwuid($>) )[7];
    my %CFG     = (
        'php_ini'      => '/usr/local/lib/php.ini',
        'bin_dir'      => $homedir . '/bin',
        'doc_dir'      => $homedir . '/php/docs',
        'ext_dir'      => $homedir . '/php/ext',
        'php_dir'      => $homedir . '/php',
        'data_dir'     => $homedir . '/php/data',
        'test_dir'     => $homedir . '/php/tests',
        'temp_dir'     => $homedir . '/tmp/pear',
        'cache_dir'    => $homedir . '/tmp/pear/cache',
        'download_dir' => $homedir . '/tmp/pear/cache'
    );
    my $layer = 'user';

    # If we are running as root, delete root's .pearrc file
    # This file is used by both /usr/local/bin/pear and /ULC/3rdparty/bin/pear,
    # and may cause conflicts between them (e.g. using the wrong php.ini).
    # See https://fogbugz.cpanel.net/default.asp?W1947 for background.
    if ( $> == 0 ) {
        my $pearrc = Cpanel::PwCache::gethomedir() . '/.pearrc';
        unlink $pearrc if -e $pearrc;

        # Make changes in the PHP installation's pear.conf, rather than the user's ~/.pearrc
        $layer = 'system';
        %CFG   = (
            'php_ini'      => '/usr/local/lib/php.ini',
            'bin_dir'      => '/usr/local/bin',
            'doc_dir'      => '/usr/local/lib/php/docs',
            'ext_dir'      => Cpanel::PHPINI::get_default_extension_dir('/usr/local'),
            'php_dir'      => '/usr/local/lib/php',
            'data_dir'     => '/usr/local/lib/php/data',
            'test_dir'     => '/usr/local/lib/php/tests',
            'temp_dir'     => $homedir . '/tmp/pear',
            'cache_dir'    => $homedir . '/tmp/pear/cache',
            'download_dir' => $homedir . '/tmp/pear/cache'
        );
    }

    $pear ||= ( Cpanel::FindBin::findbin( 'pear', [ "$PHP_PREFIX/bin", "/usr/local/bin" ] ) || 'pear' );

    # If this is the cPanel-internal PHP/PEAR, set the config values appropriately
    if ( $pear =~ /3rdparty/ ) {
        $CFG{'php_ini'} = Cpanel::Binaries::get_prefix('php') . '/etc/php.ini';
        foreach my $opt ( 'bin_dir', 'doc_dir', 'ext_dir', 'php_dir', 'data_dir', 'test_dir' ) {
            delete $CFG{$opt};
        }
    }

    # CPANEL-6786: Make this a noop if we are configuring pear system-wide
    # on an EasyApache 4 server. EA4 pear is managed outside this namespace.
    require Cpanel::Config::Httpd::EA4;
    return 1 if ( $> == 0 && $pear !~ /3rdparty/ && Cpanel::Config::Httpd::EA4::is_ea4() );

    my $command_hr = {
        'command'  => [ $pear, @pear_args ],
        'cleanenv' => {
            'http_purge' => 1,
            'keep'       => [ 'USER', 'HOME' ],
        },
    };
    foreach my $cfgopt ( keys %CFG ) {
        if ( $CFG{$cfgopt} =~ /^\Q$homedir\E/ ) {
            Cpanel::SV::untaint( $CFG{$cfgopt} );
            Cpanel::SafeDir::MK::safemkdir( $CFG{$cfgopt}, '0755' );
        }
        $command_hr->{'command'} = [ $pear, 'config-set', $cfgopt, $CFG{$cfgopt}, $layer ];
        my $output = Cpanel::SafeRun::Env::saferun_cleanenv2($command_hr);
        print $output unless $quiet;
    }

    return;
}

my $allow_demo = { allow_demo => 1 };
my $deny_demo  = {};

our %API = (
    setup          => $allow_demo,
    getprefix      => $allow_demo,
    getarchname    => $allow_demo,
    langlist       => $allow_demo,
    getkey         => $allow_demo,
    pre_run        => $allow_demo,
    list_installed => $allow_demo,
    list_available => $allow_demo,
    search         => $allow_demo,
    install        => $deny_demo,
    uninstall      => $deny_demo,
    update         => $deny_demo,
    magic_status   => $allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub mod_cleanup {
    my $mod = shift;
    $mod =~ s/[^\w:.-]+//g;
    return $mod;
}

sub _democheck {
    if ( exists $Cpanel::CPDATA{'DEMO'} && $Cpanel::CPDATA{'DEMO'} ) {
        return 1;
    }
    return;
}

sub _demomessage {
    print 'Sorry, this feature is disabled in demo mode.';
    return;
}

#####################################################################
# The below API1 calls were added because API1 is the only api we   #
# currently have that supports live streaming of data.              #
#                                                                   #
# Please do not follow this pattern if it can be avoided.           #
#####################################################################

sub api1_install {
    return _demomessage() if _democheck();
    my ( $lang, $mod ) = @_;
    return ( Cpanel::LangMods::doaction( $lang, 'install', $mod ) )[0];
}

sub api1_uninstall {
    return _demomessage() if _democheck();
    my ( $lang, $mod ) = @_;
    return ( Cpanel::LangMods::doaction( $lang, 'uninstall', $mod ) )[0];
}

sub api1_update {
    return _demomessage() if _democheck();
    my ( $lang, $mod ) = @_;
    return ( Cpanel::LangMods::doaction( $lang, 'update', $mod ) )[0];
}

our $api1 = {
    'install' => {
        'function' => \&Cpanel::LangMods::api1_install,    # not allowed to return html
    },
    'uninstall' => {
        'function' => \&Cpanel::LangMods::api1_uninstall,    # not allowed to return html
    },
    'update' => {
        'function' => \&Cpanel::LangMods::api1_update,       # not allowed to return html
    },

};

sub _get_php_type_version {
    my $selectorctl = Cpanel::FindBin::findbin( 'selectorctl', ['/usr/bin'] );

    return unless $selectorctl;

    my $username = $ENV{REMOTE_USER} || getpwuid($<);

    my $info = Cpanel::SafeRun::Env::saferun_cleanenv2(
        {
            'command'  => [ $selectorctl, '--user-current', "--user=$username" ],
            'cleanenv' => {
                'http_purge' => 1,
                'keep'       => [ 'USER', 'HOME' ],
            },
        }
    );
    my $type    = rindex( $info, '/opt/alt/' ) > 0 ? 'alt' : 'native';
    my $version = substr( $info, 0, 3 );
    $version =~ s/\.//g;
    return ( $type, $version );
}

1;
