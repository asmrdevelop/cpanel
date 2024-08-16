package Cpanel::DNSLib;

# cpanel - Cpanel/DNSLib.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::SafeStorable                 ();
use Cpanel::SafeFile                     ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::Path                         ();
use Cpanel::CommentKiller                ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Logger                       ();
use Cpanel::SafetyBits                   ();
use Cpanel::SafeRun::Errors              ();
use Cpanel::SafeRun::Simple              ();
use Cpanel::StringFunc::Trim             ();
use Cpanel::NameServer::Utils::BIND      ();
use Cpanel::DNSLib::Check                ();
use Cpanel::DNSLib::Find                 ();
use Cpanel::DNSLib::Zone                 ();
use Cpanel::DNSLib::Config               ();
use Cpanel::ConfigFiles                  ();
use Cpanel::FileUtils::Link              ();
use Cpanel::FileUtils::Copy              ();
use Cpanel::FileUtils::Move              ();
use Cpanel::FileUtils::TouchFile         ();
use Cpanel::PwCache                      ();
use Cpanel::Binaries                     ();

our $VERSION = '0.7.2';
my $logger = Cpanel::Logger->new();

################################################################################
# new - create new DNSLib object
# Arguments to new():
#   datafile - location of data store (optional)
#   namedconf - location of named.conf (optional)
#   force - cause named and rndc settings to be reread and stored (optional)
################################################################################

sub new {
    my $self = bless( {}, shift() );    # perldoc -f bless, uses  __PACKAGE__ by default
    $self->init(@_);
    return $self;
}

################################################################################
# init
################################################################################

sub init {
    my ( $self, %extra ) = @_;
    @$self{ keys %extra } = values %extra if %extra;
    $self->{'parse'} = 0;

    # Check to see if named.conf file exists.
    if ( defined( $self->{'namedconf'} ) ) {
        if ( !-e $self->{'namedconf'} ) {
            $logger->die("Bind configuration file $self->{'namedconf'} does not exist.");
        }
    }
    else {
        $self->{'namedconf'} = Cpanel::NameServer::Utils::BIND::find_namedconf();
        if ( $self->{'namedconf'} eq '' ) {
            $logger->die("Unable to locate Bind configuration file.");
        }
    }

    # Check to see if data exists.
    if ( defined( $self->{'datafile'} ) ) {
        if ( !-e $self->{'datafile'} ) {
            $logger->die('Data file does not exist.');
        }
    }
    else {
        $self->{'datafile'} = $self->find_datafile();
    }

    # Check to see if named.conf reread specified
    if ( defined( $self->{'force'} ) ) {
        $self->{'parse'} = 1;
    }

    # Load data file
    if ( !$self->{'parse'} ) {
        eval { $self->{'data'} = Cpanel::SafeStorable::retrieve( $self->{'datafile'} ); };
        if ( !defined( $self->{'data'}{'sysconfdir'} ) || $@ ) {
            if ($@) {
                $logger->warn($@);
            }
            $self->{'parse'} = 1;
        }
    }

    # Check to see if named.conf has been modified since data stored
    my $mtime = ( stat( $self->{'namedconf'} ) )[9];
    if ( defined( $self->{'data'}{'mtime'} ) ) {
        if ( $self->{'data'}{'mtime'} != $mtime ) {    #timewarp safe
            $self->{'parse'} = 1;
        }
    }
    else {
        $self->{'parse'} = 1;
    }

    # Parse named.conf if necessary
    if ( $self->{'parse'} ) {
        $self->parsebindsettings();

        # Store results
        Storable::nstore( $self->{'data'}, $self->{'datafile'} );
    }
}

################################################################################
# find_datafile
################################################################################

sub find_datafile {
    my $self     = shift;
    my $dir      = '/var/cpanel';
    my $filename = 'CPDNSLib.dat';
    if ( -e $dir ) {
        if ( !-d $dir ) { $logger->die("$dir is not a directory."); }
    }
    else {
        mkdir( $dir, 0755 ) || $logger->die("Unable to create directory: $dir");
    }
    if ( !-e $dir . '/' . $filename ) {
        open( my $f, ">", $dir . '/' . $filename )
          || $logger->die("Unable to write: ${dir}/${filename}");
        close($f);
        $self->{'force'} = 1;
    }
    return $dir . '/' . $filename;
}

################################################################################
# parsebindsettings
################################################################################

sub parsebindsettings {
    my $self = shift;

    $self->{'data'}{'mtime'}       = ( stat( Cpanel::NameServer::Utils::BIND::find_namedconf() ) )[9];
    $self->{'data'}{'zonefiledir'} = $self->find_zonedir();
    $self->{'data'}{'chrootdir'}   = $self->find_chrootbinddir();
    $self->{'data'}{'sysconfdir'}  = $self->find_sysconfdir();
    $self->{'data'}{'binduser'}    = $self->getbinduser();
    $self->{'data'}{'bindgroup'}   = $self->getbindgroup();
    $self->{'data'}{'views'}       = $self->getbindviews();
    $self->{'parse'}               = 0;
    return 1;
}

################################################################################
# removeuserdomain - dnsadmin function
################################################################################

sub removeuserdomain {
    my $self   = shift;
    my $domain = shift;
    my $user   = $self->getdomainowner($domain);
    if ( $user ne '' && $user ne '*' && $user ne 'nobody' && $user ne 'root' ) {
        my (@CFILE);
        if ( !-e "/var/cpanel/users/$user" ) { Cpanel::FileUtils::TouchFile::touchfile("/var/cpanel/users/$user") or $logger->die("Could not create /var/cpanel/users/$user"); }
        my $ulock = Cpanel::SafeFile::safeopen( \*USERDATA, '+<', '/var/cpanel/users/' . $user );
        if ( !$ulock ) {
            $logger->warn("Could not edit /var/cpanel/users/$user");
            return;
        }
        while (<USERDATA>) {
            push( @CFILE, $_ );
        }
        seek( USERDATA, 0, 0 );
        foreach (@CFILE) {
            if ( $_ !~ m/^DNS[\d]+=${domain}/ ) {
                print USERDATA $_;
            }
        }
        truncate( USERDATA, tell(USERDATA) );
        Cpanel::SafeFile::safeclose( \*USERDATA, $ulock );
    }
    return;
}

################################################################################
# getdomainowner - dnsadmin function
################################################################################

sub getdomainowner {
    my $self = shift;
    goto &Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner;
}

################################################################################
# checknamedconf - dnsadmin function
################################################################################

sub checknamedconf {
    my $self     = shift;
    my $conffile = shift || $self->{'namedconf'};

    return Cpanel::NameServer::Utils::BIND::checknamedconf($conffile);
}

# Alias a few previously subbed out/goto'd things
*checkzone      = \&Cpanel::DNSLib::Zone::checkzone;
*checkrndc      = \&Cpanel::DNSLib::Check::checkrndc;
*find_namedconf = \&Cpanel::NameServer::Utils::BIND::find_namedconf;

################################################################################
# removezone - dnsadmin function
################################################################################

sub removezone {
    my ( $self, $domain ) = @_;
    return Cpanel::DNSLib::Zone::removezone( $domain, $self->{'data'}{'zonefiledir'}, $self->{'data'}{'chrootdir'} );
}

################################################################################
# removemailaliases - dnsadmin function
################################################################################

sub removemailaliases {
    my ( $self, $domain ) = @_;
    if ( -e "$Cpanel::ConfigFiles::VALIASES_DIR/$domain" ) {
        Cpanel::FileUtils::Link::safeunlink("$Cpanel::ConfigFiles::VALIASES_DIR/$domain");
    }
    return;
}

################################################################################
# find_namedbin
################################################################################
sub find_namedbin {
    my $loc = Cpanel::Binaries::path('named');
    return -x $loc ? $loc : '';
}

###############################################################################
# rndcconf_filename
# returns the name of the rndc.conf filename whether it exists or not.
###############################################################################
sub rndcconf_filename {
    my $self       = shift;
    my $sysconfdir = $self->{'data'}{'sysconfdir'};
    return $sysconfdir . '/rndc.conf';
}

################################################################################
# find_rndcconf
# returns location of rndc.conf or undef if none is found.
################################################################################

sub find_rndcconf {
    my $self     = shift;
    my $rndcconf = $self->rndcconf_filename();

    if ( !-e $rndcconf ) {

        # Locate rndc.conf at alternative locations
        if ( -e '/etc/rndc.conf' ) {
            Cpanel::FileUtils::Link::safelink( '/etc/rndc.conf', $rndcconf );
        }
        elsif ( -e '/etc/bind/rndc.conf' ) {
            Cpanel::FileUtils::Link::safelink( '/etc/bind/rndc.conf', $rndcconf );
        }
        elsif ( -e '/etc/namedb/rndc.conf' ) {
            Cpanel::FileUtils::Link::safelink( '/etc/namedb/rndc.conf', $rndcconf );
        }
        elsif ( -e '/usr/local/etc/rndc.conf' ) {
            Cpanel::FileUtils::Link::safelink( '/usr/local/etc/rndc.conf', $rndcconf );
        }
        else {
            return;
        }
    }

    return $rndcconf;
}

################################################################################
# find_rndckey
# returns location of rndc.key
################################################################################

sub find_rndckey {
    my $self       = shift;
    my $rndckey    = '';
    my $sysconfdir = $self->{'data'}{'sysconfdir'};
    $rndckey = $sysconfdir . '/rndc.key';

    if ( !-e $rndckey ) {
        my $chrootdir = $self->{'chrootdir'};

        # Locate rndc.conf at alternative locations
        if ( -e '/etc/rndc.key' ) {
            Cpanel::FileUtils::Link::safelink( '/etc/rndc.key', $rndckey );
        }
        elsif ( -e '/etc/bind/rndc.key' ) {
            Cpanel::FileUtils::Link::safelink( '/etc/bind/rndc.key', $rndckey );
        }
        elsif ( -e '/etc/namedb/rndc.key' ) {
            Cpanel::FileUtils::Link::safelink( '/etc/namedb/rndc.key', $rndckey );
        }
        elsif ( -e '/usr/local/etc/rndc.key' ) {
            Cpanel::FileUtils::Link::safelink( '/usr/local/etc/rndc.key', $rndckey );
        }
        elsif ( $chrootdir && -e $chrootdir . '/' . $rndckey ) {
            Cpanel::FileUtils::Link::safelink( $chrootdir . '/' . $rndckey, $rndckey );
        }
        else {
            if ( open( my $rkey, ">", $rndckey ) ) {
                close($rkey);
            }
        }
    }

    my $uid = ( getpwnam( $self->{'data'}{'binduser'} ) )[2];
    my $gid = ( getgrnam( $self->{'data'}{'bindgroup'} ) )[2];

    if ( !defined $uid || !defined $gid ) {
        $logger->warn( "Error fetching uid/gid for " . $self->{'data'}{'binduser'} );
    }
    else {
        chown( $uid, $gid, $rndckey );
    }

    chmod( oct('0600'), $rndckey );

    return $rndckey;
}

################################################################################
# loadrndcconf
# returns the following
# $secret : key hash
# $keyname : the name of the key specified in the key clause
# $defaultkey : the name of the default key listed in the options clause
# else returns ""
################################################################################

sub loadrndcconf {
    my $self     = shift;
    my $rndcconf = shift;
    if ( !defined($rndcconf) || ( !-e $rndcconf ) ) {
        $rndcconf = $self->find_rndcconf() || $self->rndcconf_filename();    # If exists, return it; otherwise, use default name.
    }
    my $secret     = '';
    my $keyname    = '';
    my $defaultkey = '';
    my $keyfile    = '';

    if ( -e $rndcconf ) {
        my $numbrace      = 0;
        my $optionsmarker = 0;
        my $keymarker     = 0;

        my $commentkiller = Cpanel::CommentKiller->new;
        my $parsed;
        open( my $rndc_fh, '<', $rndcconf ) or die "Failed to open($rndcconf): $!";
        while ( readline($rndc_fh) ) {
            $parsed = tr{#*/}{} ? $commentkiller->parse($_) : $_;
            next if !$parsed || $parsed !~ tr{ \t\r\n}{}c;

            if ( $numbrace == 0 ) {
                $optionsmarker = 0;
                $keymarker     = 0;
            }
            if ($optionsmarker) {
                if ( $parsed =~ /default-key[\s\t]+[\"\']?(\S+)/ ) {
                    $defaultkey = $1;
                    $defaultkey =~ s/[\"\'\;]//g;
                }

                $numbrace += ( ( $parsed =~ tr/{// ) - ( $parsed =~ tr/}// ) );    #StringFunc::get_curly_brace_count($parsed);
            }
            if ($keymarker) {
                if ( $parsed =~ /secret[\s\t]+[\"\']([^\"\']+)/ ) {
                    $secret = $1;
                }
                $numbrace += ( ( $parsed =~ tr/{// ) - ( $parsed =~ tr/}// ) );    #StringFunc::get_curly_brace_count($parsed);
            }
            if ( ( !$optionsmarker || !$keymarker ) && $parsed =~ /^[\s\t]*options/ ) {
                if ( $parsed =~ /default-key[\s\t]+[\"\']?(\S+)/ ) {
                    $defaultkey = $1;
                    $defaultkey =~ s/[\"\'\;]//g;
                }

                $optionsmarker = 1;
                $numbrace += ( ( $parsed =~ tr/{// ) - ( $parsed =~ tr/}// ) );    #StringFunc::get_curly_brace_count($parsed);
            }
            if ( ( !$optionsmarker || !$keymarker ) && $parsed =~ /^[\s\t]*key/ ) {
                if ( $parsed =~ /^[\s\t]*key[\s\t]+[\"\']([^\"\']+)/ ) {

                    # $keyname will be set here or nowhere
                    $keyname = $1;
                    if ( $parsed =~ /secret[\s\t]+[\"\']([^\"\']+)/ ) {
                        $secret = $1;
                    }
                }
                $keymarker = 1;
                $numbrace += ( ( $parsed =~ tr/{// ) - ( $parsed =~ tr/}// ) );    #StringFunc::get_curly_brace_count($parsed);
            }
            if ( ( !$optionsmarker || !$keymarker )
                && $parsed =~ /^[\s\t]*include[\s\t]+[\"\']([^\"\']+)/ ) {
                $keyfile = $1;
            }
        }
        close($rndc_fh);

        if ( ( !$secret ) && $keyfile ) {
            ( $secret, $keyname ) = $self->loadrndckey($keyfile);
        }
    }
    return ( $secret, $keyname, $defaultkey );
}

################################################################################
# loadrndckey
# returns the following
# $secret : key hash
# $keyname : the name of the key specified in the key clause
# else returns ""
################################################################################

sub loadrndckey {
    my $self    = shift;
    my $rndckey = shift;
    if ( ( !defined($rndckey) ) || ( !-e $rndckey ) ) {
        $rndckey = $self->find_rndckey();
    }
    my $secret  = '';
    my $keyname = '';

    if ( -e $rndckey ) {
        my $numbrace  = 0;
        my $keymarker = 0;

        my $commentkiller = Cpanel::CommentKiller->new;
        my $parsed;
        open( my $rndc_fh, '<', $rndckey ) or die "Failed to open($rndckey): $!";
        while ( readline($rndc_fh) ) {
            $parsed = tr{#*/}{} ? $commentkiller->parse($_) : $_;
            next if !$parsed || $parsed !~ tr{ \t\r\n}{}c;

            if ( $numbrace == 0 ) {
                $keymarker = 0;
            }
            if ($keymarker) {
                if ( $parsed =~ /secret[\s\t]+[\"\']([^\"\']+)/ ) {
                    $secret = $1;
                }
                $numbrace += ( ( $parsed =~ tr/{// ) - ( $parsed =~ tr/}// ) );    #StringFunc::get_curly_brace_count($parsed);
            }
            if ( ( !$keymarker ) && $parsed =~ /^[\s\t]*key/ ) {
                if ( $parsed =~ /^[\s\t]*key[\s\t]+[\"\']([^\"\']+)/ ) {

                    # $keyname will be set here or nowhere
                    $keyname = $1;
                    $keyname =~ s/[\"\'\;]//g;
                    if ( $parsed =~ /secret[\s\t]+[\"\']([^\"\']+)/ ) {
                        $secret = $1;
                    }
                }
                $keymarker = 1;
                $numbrace += ( ( $parsed =~ tr/{// ) - ( $parsed =~ tr/}// ) );    #StringFunc::get_curly_brace_count($parsed);
            }
        }

        close($rndc_fh);

    }
    return ( $secret, $keyname );
}

################################################################################
# find_rndc
# returns location of rndc or '' if not found
################################################################################

sub find_rndc {
    goto &Cpanel::DNSLib::Find::find_rndc;
}

################################################################################
# find_rndcconfgen
# returns location of rndc-confgen or "" if not found
################################################################################

sub find_rndcconfgen {
    my $loc = Cpanel::Binaries::path('rndc-confgen');
    return -x $loc ? $loc : '';
}

################################################################################
# getrndcsettings
# returns the following from named.conf:
#
# $key : key clause, 1 if exists 0 otherwise
# $keykeyname : name of rndc key specified in key clause
# $secret : hash specified in key clause
# $controls : control clause, 1 if exists 0 otherwise
# $inet : IP specified for inet in control clause
# $allow : hosts specified for allow in control clause
# $controlskeyname : name of key specified for keys in control clause else "" if not found
# $rncd_include : include line for rndc.conf 1 if exists, 0 otherwise
#
################################################################################

sub getrndcsettings {
    my $self    = shift;
    my $rndckey = shift;

    if ( ( !defined($rndckey) ) || ( !-e $rndckey ) ) {
        $rndckey = $self->find_rndckey();
    }

    my $key             = 0;
    my $keykeyname      = '';
    my $secret          = '';
    my $controls        = 0;
    my $inet            = '';
    my $allow           = '';
    my $controlskeyname = '';
    my $rndc_include    = 0;

    my $namedconf = $self->{'namedconf'};

    if ( $namedconf ne '' ) {
        my $controlsmarker = 0;
        my $keymarker      = 0;
        my $numbrace       = 0;

        my $commentkiller = Cpanel::CommentKiller->new;
        my $parsed;
        open( my $ndc_fh, '<', $namedconf ) or die "Failed to open($namedconf): $!";
        while ( readline($ndc_fh) ) {
            $parsed = tr{#*/}{} ? $commentkiller->parse($_) : $_;
            next if !$parsed || $parsed !~ tr{ \t\r\n}{}c;

            if ( $numbrace == 0 ) {
                $controlsmarker = 0;
                $keymarker      = 0;
            }
            if ($controlsmarker) {
                if ( $parsed =~ /keys[\s\t]*\{[\s\t]*[\"\']([^\"\']+)/ ) {
                    $controlskeyname = $1;
                }
                if ( $parsed =~ /inet[\s\t]+(\d+\.\d+\.\d+\.\d+)/ ) {
                    $inet = $1;
                }
                if ( $parsed =~ /inet[\s\t]+(\*)/ ) {
                    $inet = $1;
                }
                if ( $parsed =~ /allow[\s\t]+\{[\s\t]+([^\}]+)/ ) {
                    $allow = $1;
                }
                $numbrace += ( ( $parsed =~ tr/{// ) - ( $parsed =~ tr/}// ) );    #StringFunc::get_curly_brace_count($parsed);
            }
            if ($keymarker) {
                if ( $parsed =~ /secret[\s\t]+[\"\']([^\"\']+)/ ) {
                    $secret = $1;
                }
                $numbrace += ( ( $parsed =~ tr/{// ) - ( $parsed =~ tr/}// ) );    #StringFunc::get_curly_brace_count($parsed);
            }
            if ( !$keymarker || !$controlsmarker ) {
                if ( $parsed =~ /^[\s\t]*controls/ ) {
                    if ( $parsed =~ /keys[\s\t]*\{[\s\t]*[\"\']([^\"\']+)/ ) {
                        print $1 . "\n\n";
                        $controlskeyname = $1;
                    }
                    if ( $parsed =~ /inet[\s\t]+(\d+\.\d+\.\d+\.\d+)/ ) {
                        $inet = $1;
                    }
                    if ( $parsed =~ /inet[\s\t]+(\*)/ ) {
                        $inet = $1;
                    }
                    if ( $parsed =~ /allow[\s\t]+\{[\s\t]+([^\}]+)/ ) {
                        $allow = $1;
                    }

                    $controls       = 1;
                    $controlsmarker = 1;
                    $numbrace += ( ( $parsed =~ tr/{// ) - ( $parsed =~ tr/}// ) );    #StringFunc::get_curly_brace_count($parsed);
                }
                elsif ( $parsed =~ /^[\s\t]*key/ ) {
                    if ( $parsed =~ /^[\s\t]*key[\s\t]+[\"\']([^\"\']+)/ ) {

                        # $keykeyname will be set here or nowhere
                        $keykeyname = $1;
                        if ( $parsed =~ /secret[\s\t]+[\"\']([^\"\']+)/ ) {
                            $secret = $1;
                        }
                    }
                    $key       = 1;
                    $keymarker = 1;
                    $numbrace += ( ( $parsed =~ tr/{// ) - ( $parsed =~ tr/}// ) );    #StringFunc::get_curly_brace_count($parsed);
                }
                elsif ( $parsed =~ /^\s*include\s+[\"\']([^\"\']+)[\"\']/ ) {
                    $rndc_include = 1 if ( $1 eq $rndckey );
                }
            }
        }
        close($ndc_fh);
    }
    if ( $allow ne "" ) { $allow =~ s/[\;\s]//g; }
    return ( $key, $keykeyname, $secret, $controls, $inet, $allow, $controlskeyname, $rndc_include );
}

################################################################################
# find_chrootbinddir
# returns chroot directory if not null, else returns ""
################################################################################

sub find_chrootbinddir {
    goto &Cpanel::NameServer::Utils::BIND::find_chrootbinddir;
}

################################################################################
# find_zonedir
# returns location of zone file dir as specified in named.conf
# OR /var/named (as this is the default).
################################################################################

sub find_zonedir {
    my $self        = shift;
    my $zonefiledir = '';
    my $namedconf   = $self->{'namedconf'};

    if ($namedconf) {
        my $hasoptions = 0;

        my $commentkiller = Cpanel::CommentKiller->new;
        my $parsed;
        open( my $ndc_fh, '<', $namedconf ) or die "Failed to open($namedconf): $!";
        while ( readline($ndc_fh) ) {
            $parsed = tr{#*/}{} ? $commentkiller->parse($_) : $_;
            next if !$parsed || $parsed !~ tr{ \t\r\n}{}c;

            if ($hasoptions) {
                if ( $parsed =~ m/directory\s+["']?([^"']+)/ ) {
                    $zonefiledir = $1;
                    last;
                }
            }
            if ( $parsed =~ m/^[\s\t]*options/ ) {
                if ( $parsed =~ m/directory\s+["']?([^"']+)/ ) {
                    $zonefiledir = $1;
                    last;
                }
                else {
                    $hasoptions = 1;
                    next;
                }
            }
        }
        close($ndc_fh);
    }
    $zonefiledir = Cpanel::StringFunc::Trim::endtrim( $zonefiledir, '/' );
    return $zonefiledir || '/var/named';
}

################################################################################
# setupbindchroot
# creates appropriate chroot environment for Bind
################################################################################

sub setupbindchroot {
    my $self       = shift;
    my $chrootdir  = $self->{'data'}{'chrootdir'};
    my $zonedir    = $self->{'data'}{'zonefiledir'};
    my $sysconfdir = $self->{'data'}{'sysconfdir'};
    my $binduser   = $self->{'data'}{'binduser'};
    my $bindgrp    = $self->{'data'}{'bindgroup'};

    if ( -l $chrootdir ) {
        $chrootdir = Cpanel::Path::relative2abspath( readlink($chrootdir), Cpanel::Path::getdir($chrootdir) );
    }
    if ( -e $chrootdir ) {
        Cpanel::SafeRun::Errors::saferunnoerror( 'chattr', '-R', '-i', $chrootdir );
    }
    if ( !-d $chrootdir ) {
        if ( -e $chrootdir ) {
            $logger->warn("Moving $chrootdir to ${chrootdir}.cpbackup");
            Cpanel::FileUtils::Move::safemv( $chrootdir, $chrootdir . '.cpbackup' );
        }
        Cpanel::SafeDir::MK::safemkdir($chrootdir);
    }
    if ( !-d $chrootdir . $zonedir ) {
        if ( -e $chrootdir . $zonedir ) {
            $logger->warn("Moving ${chrootdir}${zonedir} to ${chrootdir}${zonedir}.cpbackup");
            Cpanel::FileUtils::Move::safemv( $chrootdir . $zonedir, $chrootdir . $zonedir . '.cpbackup' );
        }
        Cpanel::SafeDir::MK::safemkdir( $chrootdir . $zonedir );
    }
    if ( !-d $chrootdir . $sysconfdir ) {
        if ( -e $chrootdir . $sysconfdir ) {
            $logger->warn("Moving ${chrootdir}${sysconfdir} to ${chrootdir}${sysconfdir}.cpbackup");
            Cpanel::FileUtils::Move::safemv( $chrootdir . $sysconfdir, $chrootdir . $sysconfdir . '.cpbackup' );
        }
        Cpanel::SafeDir::MK::safemkdir( $chrootdir . $sysconfdir );
    }
    if ( !-d $chrootdir . '/dev' ) {
        if ( -e $chrootdir . '/dev' ) {
            $logger->warn("Moving ${chrootdir}/dev to ${chrootdir}/dev.cpbackup");
            Cpanel::FileUtils::Move::safemv( $chrootdir . '/dev', $chrootdir . '/dev.cpbackup' );
        }
        Cpanel::SafeDir::MK::safemkdir( $chrootdir . '/dev' );
    }

    if ( !-d $chrootdir . '/var/run/named' ) {
        if ( -e $chrootdir . '/var/run/named' ) {
            Cpanel::FileUtils::Move::safemv( $chrootdir . '/var/run/named', $chrootdir . '/var/run/named.cpback' );
        }
        Cpanel::SafeDir::MK::safemkdir( $chrootdir . '/var/run/named' );
    }
    else {
        Cpanel::SafeDir::MK::safemkdir( $chrootdir . '/var/run/named' );
    }
    if ( -e $chrootdir . '/dev/null' ) {
        if ( !-c $chrootdir . '/dev/null' ) {
            Cpanel::FileUtils::Move::safemv( $chrootdir . '/dev/null', $chrootdir . '/dev/null.cpbackup' );
            Cpanel::SafeRun::Simple::saferun( 'mknod', $chrootdir . '/dev/null', 'c', '1', '3' );
        }
    }
    else {
        Cpanel::SafeRun::Simple::saferun( 'mknod', $chrootdir . '/dev/null', 'c', '1', '3' );
    }
    if ( -e $chrootdir . '/dev/random' ) {
        if ( !-c $chrootdir . '/dev/random' ) {
            Cpanel::FileUtils::Move::safemv( $chrootdir . '/dev/random', $chrootdir . '/dev/random.cpbackup' );
            Cpanel::SafeRun::Simple::saferun( 'mknod', $chrootdir . '/dev/random', 'c', '1', '8' );
        }
    }
    else {
        Cpanel::SafeRun::Simple::saferun( 'mknod', $chrootdir . '/dev/random', 'c', '1', '8' );
    }
    if ( -e $chrootdir . '/dev/urandom' ) {
        if ( !-c $chrootdir . '/dev/urandom' ) {
            Cpanel::FileUtils::Move::safemv( $chrootdir . '/dev/urandom', $chrootdir . '/dev/urandom.cpbackup' );
            Cpanel::SafeRun::Simple::saferun( 'mknod', $chrootdir . '/dev/urandom', 'c', '1', '9' );
        }
    }
    else {
        Cpanel::SafeRun::Simple::saferun( 'mknod', $chrootdir . '/dev/urandom', 'c', '1', '9' );
    }
    if ( !-e $chrootdir . '/etc/localtime' && -e '/etc/localtime' ) {
        Cpanel::SafeRun::Simple::saferun( 'cp', '/etc/localtime', $chrootdir . '/etc/localtime' );
    }
    Cpanel::SafetyBits::safe_recchown( $binduser, $bindgrp, $chrootdir );
    return 0;
}

################################################################################
# find_sysconfdir
# returns location of sysconfdir
################################################################################

sub find_sysconfdir {
    my $self       = shift;
    my $sysconfdir = '/etc';

    if ( !-d $sysconfdir ) {
        $logger->warn('The default sysconfdir is not a directory, attempting to create');
        if ( -e $sysconfdir ) {
            $logger->die("$sysconfdir exists, but is not a directory");
        }
        else {
            Cpanel::SafeDir::MK::safemkdir($sysconfdir);
        }
    }
    return $sysconfdir;
}

################################################################################
# getbinduser
# returns system user for Bind
################################################################################

sub getbinduser {
    my $self = shift;
    return 'named';
}

################################################################################
# getbindgroup
# returns system group for Bind
################################################################################

sub getbindgroup {
    my $self = shift;
    return 'named';
}

################################################################################
# getbindview
# returns hash ref of all veiws in named.conf
################################################################################

sub getbindviews {
    my $self = shift;
    my %VIEWS;
    my $namedconf = $self->{'namedconf'};

    if ($namedconf) {
        my $commentkiller = Cpanel::CommentKiller->new;
        my $parsed;
        open( my $ndc_fh, '<', $namedconf ) or die "Failed to open($namedconf): $!";
        while ( readline($ndc_fh) ) {
            $parsed = tr{#*/}{} ? $commentkiller->parse($_) : $_;
            next if !$parsed || $parsed !~ tr{ \t\r\n}{}c;

            if ( $parsed =~ m/^\s*view\s+/ ) {
                if ( $parsed =~ m/^\s*view\s+["']([^"']+)/ ) {
                    my $view = $1;
                    $VIEWS{$view} = q{};
                    if ( $parsed =~ m/^\s*view\s+["'][^"']+["']\s+(\S+)/ ) {
                        if ( $1 ne '{' ) {
                            $VIEWS{$view} = $1;
                        }
                    }
                }
                elsif ( $parsed =~ m/^\s*view\s+(\S+)/ ) {
                    my $view = $1;
                    $VIEWS{$view} = q{};
                    if ( $parsed =~ m/^\s*view\s+\S+\s+(\S+)/ ) {
                        if ( $1 ne '{' ) {
                            $VIEWS{$view} = $1;
                        }
                    }
                }
            }
        }
        close($ndc_fh);
    }
    return \%VIEWS;
}

sub getdnspeerlist {
    goto &Cpanel::DNSLib::Config::getdnspeerlist;
}

sub getdnspeers {
    goto &Cpanel::DNSLib::Config::getdnspeers;
}

sub getclusteruserpass {
    goto &Cpanel::DNSLib::Config::getclusteruserpass;
}

sub removeview {
    my $self = shift;
    my $view = shift;
    return if !$view;

    my $namedconf = $self->{'namedconf'};

    my $numbrace;
    my $inview;
    if ( !-e $namedconf ) { $logger->die("Could not find $namedconf , please correct and try again"); }    # don't want to create an empty named.conf and treat it like it's ok..
    my $ndclock = Cpanel::SafeFile::safeopen( \*NDC, "+<", $namedconf );
    if ( !$ndclock ) {
        $logger->warn("Could not edit $namedconf");
        return;
    }
    my @NDC = <NDC>;
    seek( NDC, 0, 0 );
    my $parsed;
    my $commentkiller = Cpanel::CommentKiller->new;
    foreach (@NDC) {
        $parsed = tr{#*/}{} ? $commentkiller->parse($_) : $_;
        next if !$parsed || $parsed !~ tr{ \t\r\n}{}c;
        if ($inview) {
            if ( $inview ne $view ) {
                print NDC $_;
            }
            $numbrace += ( ( $parsed =~ tr/{// ) - ( $parsed =~ tr/}// ) );    #StringFunc::get_curly_brace_count($parsed);
            if ( $numbrace == 0 ) {
                $inview = 0;
            }
        }
        elsif (m/^\s*view\s*["]($view)["]/) {
            $inview   = $1;
            $numbrace = 0;
            $numbrace += ( ( $parsed =~ tr/{// ) - ( $parsed =~ tr/}// ) );    #StringFunc::get_curly_brace_count($parsed);
            if ( $inview ne $view ) {
                print NDC $_;
            }
        }
        else {
            print NDC $_;
        }
    }
    truncate( NDC, tell(NDC) );

    Cpanel::SafeFile::safeclose( \*NDC, $ndclock );

    my $chrootdir = $self->{'data'}{'chrootdir'};
    if ( $chrootdir ne '' ) {
        Cpanel::FileUtils::Copy::safecopy( $namedconf, $chrootdir . $namedconf );
        Cpanel::SafetyBits::safe_chown_guess_gid( $self->{'data'}{'binduser'}, $chrootdir . $namedconf );
    }
    return 1;
}

sub editviewdirective {
    my $self        = shift;
    my $view        = shift;
    my $directive   = shift;
    my $replacement = shift;
    my $updated     = 0;
    return if !$view;

    my $namedconf = $self->{'namedconf'};

    my $numbrace;
    my $inview;
    if ( !-e $namedconf ) { $logger->die("Could not find $namedconf , please correct and try again"); }    # don't want to create an empty named.conf and treat it like it's ok..
    my $ndclock = Cpanel::SafeFile::safeopen( \*NDC, "+<", $namedconf );
    if ( !$ndclock ) {
        $logger->warn("Could not edit $namedconf");
        return;
    }
    my @NDC = <NDC>;
    seek( NDC, 0, 0 );

    foreach (@NDC) {
        if ($inview) {
            if ( $inview ne $view ) {
                print NDC $_;
            }
            else {
                if (m/^\s*${directive}$/) {
                    $updated = 1;
                    if ($replacement) {
                        print NDC $replacement;
                    }
                }
                else {
                    print NDC $_;
                }
            }
            $numbrace += ( ( $_ =~ tr/{// ) - ( $_ =~ tr/}// ) );    #StringFunc::get_curly_brace_count($_);
            if ( $numbrace == 0 ) {
                $inview = 0;
            }
        }
        elsif ( index( $_, 'view' ) > -1 && m/^\s*view\s*["]($view)["]/ ) {
            $inview   = $1;
            $numbrace = 0;
            $numbrace += ( ( $_ =~ tr/{// ) - ( $_ =~ tr/}// ) );    #StringFunc::get_curly_brace_count($_);
            if ( $inview ne $view ) {
                print NDC $_;
            }
            else {
                if (m/^\s*${directive}$/) {
                    $updated = 1;
                    if ($replacement) {
                        print NDC $replacement;
                    }
                }
                else {
                    print NDC $_;
                }
            }
        }
        else {
            print NDC $_;
        }
    }
    truncate( NDC, tell(NDC) );

    # Check syntax
    my ( $status, $message );
    if ($updated) {
        ( $status, $message ) = $self->checknamedconf();
    }
    else {
        $status  = 1;
        $message = 'no update';
    }
    if ($status) {    # OK
        Cpanel::SafeFile::safeclose( \*NDC, $ndclock );

        my $chrootdir = $self->{'data'}{'chrootdir'};
        if ( $chrootdir ne '' ) {
            Cpanel::FileUtils::Copy::safecopy( $namedconf, $chrootdir . $namedconf );
            Cpanel::SafetyBits::safe_chown_guess_gid( $self->{'data'}{'binduser'}, $chrootdir . $namedconf );
        }

        if ($updated) {
            return wantarray ? ( 1, "View $view updated." ) : 1;
        }
        else {
            return wantarray ? ( 0, "Bind configuration OK. No matching directive found." ) : 0;
        }
    }
    else {    # FAILED
        $logger->warn("Unable to edit view $view directive: $message");
        seek( NDC, 0, 0 );
        print NDC join( '', @NDC );
        truncate( NDC, tell(NDC) );
        Cpanel::SafeFile::safeclose( \*NDC, $ndclock );
        return wantarray ? ( 0, "View update failed: $message" ) : 0;
    }
}

######[ Copy given file to chroot ]################################################################

sub copytochroot {    ## no critic (Subroutines::ProhibitExcessComplexity) - its own project
    my $self       = shift;
    my $chrootdir  = $self->{'data'}{'chrootdir'};
    my $zonedir    = $self->{'data'}{'zonefiledir'};
    my $sysconfdir = $self->{'data'}{'sysconfdir'};
    my $binduser   = $self->{'data'}{'binduser'};
    my $bindgroup  = $self->{'data'}{'bindgroup'};

    my $cpverbose = $self->{'data'}{'cpverbose'};
    my $binduid   = ( Cpanel::PwCache::getpwnam($binduser) )[2];
    my $bindgid   = ( getgrnam($bindgroup) )[2];

    my $filenew = shift;

    # mtime of original file
    my $mtime = shift || 0;

    if ( $chrootdir ne '' ) {
        my $chrootfile = $chrootdir . $filenew;
        print "Copying $filenew to $chrootfile\n" if $cpverbose;
        my ( $fsinode, $fsmode, $fsuid, $fsgid, $fsmtime ) = ( stat($filenew) )[ 1, 2, 4, 5, 9 ];
        my $fsperms = $fsmode & 07777;
        if ( -e $chrootfile ) {
            my ( $chrootinode, $chrootmode, $chrootuid, $chrootgid, $chrootmtime ) = ( stat(_) )[ 1, 2, 4, 5, 9 ];
            my $chrootperms = $chrootmode & 07777;
            if ($mtime) {
                my $now = time();
                if ( $fsinode != $chrootinode
                    && ( $mtime > $chrootmtime || $mtime > $now || $chrootmtime > $now || $chrootuid != $binduid || $chrootgid != $bindgid || $chrootperms != $fsperms ) ) {    #timewarp safe
                    if ( Cpanel::FileUtils::Copy::safecopy( $filenew, $chrootfile ) ) {
                        print "Copied $filenew to chroot environment.\n" if $cpverbose;
                        Cpanel::SafetyBits::safe_chown_guess_gid( $binduser, $chrootfile );
                        Cpanel::SafetyBits::safe_chmod( $fsperms, $chrootfile );
                        return 1;
                    }
                    else {
                        warn "Problem copying $filenew to $chrootdir";
                        return 0;
                    }
                }
                else {
                    print "$filenew already exists in chroot environment.\n" if $cpverbose;
                    return 1;
                }
            }
            else {
                if ( $fsinode != $chrootinode ) {
                    if ( Cpanel::FileUtils::Copy::safecopy( $filenew, $chrootfile ) ) {
                        Cpanel::SafetyBits::safe_chown_guess_gid( $binduser, $chrootfile );
                        Cpanel::SafetyBits::safe_chmod( $fsperms, $chrootfile );
                        print "Copied $filenew to chroot environment.\n" if $cpverbose;
                        return 1;
                    }
                    else {
                        warn "Problem copying $filenew to $chrootdir";
                        return 0;
                    }
                }
                else {
                    if ( $chrootuid != $binduid || $chrootgid != $bindgid || $chrootperms != $fsperms ) {
                        Cpanel::SafetyBits::safe_chown_guess_gid( $binduser, $chrootfile );
                        Cpanel::SafetyBits::safe_chmod( $fsperms, $chrootfile );
                    }
                    print "$filenew already exists in chroot environment.\n" if $cpverbose;
                    return 1;
                }
            }
            warn "Problem copying $filenew to chroot environment. This should not happen.";
            return 0;
        }
        elsif ( Cpanel::FileUtils::Copy::safecopy( $filenew, $chrootfile ) ) {
            print "Copied $filenew to chroot environment.\n" if $cpverbose;
            Cpanel::SafetyBits::safe_chown_guess_gid( $binduser, $chrootfile );
            return 1;
        }
        else {
            warn "Problem copying $filenew to chroot environment.\n";
            return 0;
        }
    }
    return 0;

}

1;
