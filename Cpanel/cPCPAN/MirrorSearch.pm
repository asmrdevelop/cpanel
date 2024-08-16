package Cpanel::cPCPAN::MirrorSearch;

# cpanel - Cpanel/cPCPAN/MirrorSearch.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cwd                     ();
use Cpanel::LoadModule      ();
use Cpanel::Config::Sources ();

our $USING_CPAN = 0;

my $CPSRC      = Cpanel::Config::Sources::loadcpsources();
my $httpupdate = $CPSRC->{'HTTPUPDATE'};
my @GOODURLS;
my $GOODURLTTL       = 16384;
my $MIRROR_SPEED_TTL = 14400;
my $hassigint        = 0;
my $cpanbasedir      = $> == 0 ? '/home' : ( getpwuid($>) )[7];
my $basedir          = $cpanbasedir;

$SIG{'INT'} = sub {
    $hassigint = 1;
    print "SIGINT received.  Cleaning up and halting operations.\n\n";
};

sub checkedcpan {
    require Cpanel::FileUtils::TouchFile;
    if ( !-e "$basedir/.cpcpan" ) {
        mkdir( "$basedir/.cpcpan", 0700 );
        Cpanel::FileUtils::TouchFile::touchfile("$basedir/.cpcpan/modulecheck");
        return 0;
    }
    if ( ( ( stat("$basedir/.cpcpan/modulecheck") )[9] + 86400 ) < time() ) {
        Cpanel::FileUtils::TouchFile::touchfile("$basedir/.cpcpan/modulecheck");
        return 0;
    }
    return 1;
}

sub get_excluded_mirror_list {
    my @excluded = ('mirror.uta.edu');    # Consistently faulty mirror
    if ( open my $fh, '<', '/var/cpanel/conf/cpcpan/mirror_exclude.lst' ) {
        while ( my $line = readline $fh ) {
            chomp $line;
            if ( $line =~ m/^[a-zA-Z0-9\-\.]+$/ ) {
                push @excluded, lc $line;
            }
        }
        close $fh;
    }
    return @excluded;
}

sub getmirrorlist {    ## no critic(Subroutines::ProhibitExcessComplexity)
    my %OPTS = @_;
    my $now  = time;
    if ( $OPTS{'prefer_cache'} ) {
        if (@GOODURLS) {
            return wantarray ? @GOODURLS : \@GOODURLS;
        }
        elsif ( -e "$cpanbasedir/.cpcpan/goodurls" && _goodurls_ttl_ok( "$cpanbasedir/.cpcpan/goodurls", $now ) ) {
            my @excluded = get_excluded_mirror_list();
            if ( open( my $good_urls_fh, '<', "$cpanbasedir/.cpcpan/goodurls" ) ) {
                while ( my $mirror = readline($good_urls_fh) ) {
                    chomp $mirror;
                    if ( $mirror =~ m/^[a-zA-Z0-9\-\.]+$/ ) {

                        # Prevent excluded mirrors from being ever used
                        if ( $mirror =~ m/(?:[^\:]+):\/\/([^\/]+)/ ) {
                            my $host = lc $1;
                            next if grep { $_ eq $host } @excluded;
                        }

                        push @GOODURLS, $_;
                    }
                }
                close $good_urls_fh;
            }
        }
        if (@GOODURLS) {
            return wantarray ? @GOODURLS : \@GOODURLS;
        }
    }
    else {
        @GOODURLS = ();
    }

    my @CPANFILES = ( "$cpanbasedir/.cpan/sources/authors/01mailrc.txt.gz", "$cpanbasedir/.cpan/sources/modules/02packages.details.txt.gz", "$cpanbasedir/.cpan/sources/modules/03modlist.data.gz" );

    foreach my $cpanfile (@CPANFILES) {
        if ( -e $cpanfile ) {
            my $size = ( stat($cpanfile) )[7];
            if ( $size < 2000 ) {
                print "Removing corrupted/broken cpan file $cpanfile\n";
                unlink $cpanfile;
            }
        }
    }

    if ( !-e "$basedir/.cpcpan" ) {
        mkdir( "$basedir/.cpcpan", 0700 );
    }

    require Cpanel::HttpRequest;
    my $httpClient = Cpanel::HttpRequest->new( 'protocol' => 1, 'speed_test_file' => '/' );

    if ( !-e "$basedir/.cpcpan/MIRRORED.BY"
        || ( ( ( stat("$basedir/.cpcpan/MIRRORED.BY") )[9] + ( 86400 * 7 ) ) < $now ) ) {
        print 'Fetching CPAN mirrors...';
        $httpClient->httpreq( $httpupdate, '/pub/CPAN/MIRRORED.BY', "$basedir/.cpcpan/MIRRORED.BY" );
        if ( !-e "$basedir/.cpcpan/MIRRORED.BY" ) {
            die 'Cannot fetch mirror list from: ' . $httpupdate;
        }
        print "Done\n";
    }

    if ( !-e "$basedir/.cpcpan/MIRRORING.FROM"
        || ( ( ( stat("$basedir/.cpcpan/MIRRORING.FROM") )[9] + ( 86400 * 2 ) ) < $now ) ) {
        print 'Fetching CPAN timestamp...';
        $httpClient->httpreq( $httpupdate, '/pub/CPAN/MIRRORING.FROM', "$basedir/.cpcpan/MIRRORING.FROM" );
        if ( !-e "$basedir/.cpcpan/MIRRORING.FROM" ) {
            die 'Cannot fetch mirror timestamp file from: ' . $httpupdate;
        }
        print "Done\n";
    }

    my $mirroringfrom = get_epoch_seconds_file("$basedir/.cpcpan/MIRRORING.FROM");

    my @excluded = get_excluded_mirror_list();

    my %URLS;
    open( my $mr_fh, '<', "$basedir/.cpcpan/MIRRORED.BY" );
    while ( readline($mr_fh) ) {
        if (/^\s*dst_http\s*=\s*(\S+)/i) {
            my $mirror = $1;
            $mirror =~ s/["]//g;
            if ( $mirror =~ m/(?:[^\:]+):\/\/([^\/]+)/ ) {
                my $host = lc $1;

                # Prevent excluded mirrors from being ever used
                next if grep { $_ eq $host } @excluded;
                $URLS{$host} = $mirror . '/';
            }
        }
    }
    close($mr_fh);

    my %FALLBACKHOSTS;
    {
        my $host       = 'httpupdate.cpanel.net';
        my $gotservers = 0;
        if ( !$gotservers ) {
            require Cpanel::SocketIP;
            my @trueaddresses = Cpanel::SocketIP::_resolveIpAddress($host);
            foreach my $ip (@trueaddresses) {
                if ( $ip =~ m/^(\d+\.\d+\.\d+\.\d+)$/ ) {
                    $gotservers        = 1;
                    $URLS{$1}          = 'http://' . $1 . '/pub/CPAN/';
                    $FALLBACKHOSTS{$1} = 1;
                }
            }
        }
        if ( !$gotservers ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::DnsRoots');
            my @NSRESULT = 'Cpanel::DnsRoots'->can('fetchnameservers')->( $host, 1 );
            if ( @NSRESULT && $NSRESULT[0] == 1 && ref $NSRESULT[1] eq 'ARRAY' ) {
                my @ZONE = 'Cpanel::DnsRoots'->can('dig')->( $NSRESULT[1], $host, 'TXT', 30 );
                foreach my $line (@ZONE) {
                    chomp $line;
                    if ( $line =~ m/\s+TXT\s+\"(httpupdate\d+\.cpanel\.net)/ ) {
                        $gotservers        = 1;
                        $URLS{$1}          = 'http://' . $1 . '/pub/CPAN/';
                        $FALLBACKHOSTS{$1} = 1;
                    }
                }
            }
        }
        if ( !$gotservers ) {
            $URLS{$host}          = 'http://' . $1 . '/pub/CPAN/';
            $FALLBACKHOSTS{$host} = 1;
        }
    }

    print 'Testing connection speed...(using fast method)...';
    update_ping_times( \%URLS );
    print "Done\n";

    my %MIRROR_INFO;
    opendir( PT, "$basedir/.cpcpan/pingtimes" );
    my @PT = readdir(PT);
    closedir(PT);
    foreach my $host (@PT) {
        next if ( $host =~ /^\./ );
        if ( open my $pingtimes_fh, '<', "$basedir/.cpcpan/pingtimes/$host" ) {
            $MIRROR_INFO{$host}->{'ping'} = <$pingtimes_fh>;
            chomp( $MIRROR_INFO{$host}->{'ping'} );
            close $pingtimes_fh;
        }
    }
    undef @PT;

    if ( open my $mirrorspeeds_fh, '<', "$basedir/.cpcpan/mirrors.speeds" ) {
        while (<$mirrorspeeds_fh>) {
            chomp;
            my ( $host, $speed, $mirrortime, $mtime ) = split( /=/, $_ );
            next if ( !defined $host || $host eq '' || $mirrortime + ( 86400 * 3 ) < $mirroringfrom || !$mtime );
            $MIRROR_INFO{$host}->{'speed'} = $speed;
            $MIRROR_INFO{$host}->{'time'}  = $mirrortime;
            $MIRROR_INFO{$host}->{'mtime'} = $mtime;
        }
        close $mirrorspeeds_fh;
    }
    else {
        if ( -e "$basedir/.cpcpan/mirrors.speeds" ) { warn "Unable to read CPAN mirror speeds: $!"; }
    }

    my $primary_count = 0;
    foreach my $host ( sort { $MIRROR_INFO{$b}->{'speed'} <=> $MIRROR_INFO{$a}->{'speed'} || $MIRROR_INFO{$a}->{'ping'} <=> $MIRROR_INFO{$b}->{'ping'} } keys %URLS ) {
        next if ( $FALLBACKHOSTS{$host} );
        if ( $primary_count >= 5 ) { print "Five usable mirrors located\n"; last; }    # this has been increased for cpanminus as it finds modules faster then some CPAN mirrors update

        print "Ping:$MIRROR_INFO{$host}->{'ping'} (ticks) ";
        if ( $MIRROR_INFO{$host}->{'speed'} && $MIRROR_INFO{$host}->{'mtime'} + $MIRROR_SPEED_TTL > $now ) {
            print "Testing connection speed to $host using pureperl...";
            print "(cached .. $MIRROR_INFO{$host}->{'speed'} bytes/s)...Done\n";
            $primary_count++;
            next;
        }
        my ( $mirrorspeed, $mirrortime ) = testmirrorspeed( $host, $URLS{$host}, $mirroringfrom );
        if ( $mirrorspeed > 1 ) { $primary_count++; }
        $MIRROR_INFO{$host}->{'speed'} = $mirrorspeed;
        $MIRROR_INFO{$host}->{'time'}  = $mirrortime;
        $MIRROR_INFO{$host}->{'mtime'} = $now;
    }

    my $fallback_count = 0;
    foreach my $host ( sort { $MIRROR_INFO{$b}->{'speed'} <=> $MIRROR_INFO{$a}->{'speed'} || $MIRROR_INFO{$a}->{'ping'} <=> $MIRROR_INFO{$b}->{'ping'} } keys %FALLBACKHOSTS ) {
        if ( $fallback_count >= 3 ) { print "Three usable fallback mirrors located\n"; last; }
        print "Ping:$MIRROR_INFO{$host}->{'ping'} (ticks) ";
        if ( $MIRROR_INFO{$host}->{'speed'} && $MIRROR_INFO{$host}->{'mtime'} + $MIRROR_SPEED_TTL > $now ) {
            print "Testing connection speed to $host using pureperl...";
            print "(using cached speed)...Done\n";
            $fallback_count++;
            next;
        }

        my ( $mirrorspeed, $mirrortime ) = testmirrorspeed( $host, $URLS{$host}, $mirroringfrom );
        if ( $mirrorspeed > 1 ) {
            $mirrorspeed = ( $mirrorspeed / int( '1' . ( '0' x ( length $mirrorspeed - 1 ) ) ) ) || 1;    #always try last as a fallback
            $fallback_count++;
        }
        $MIRROR_INFO{$host}->{'speed'} = $mirrorspeed;
        $MIRROR_INFO{$host}->{'time'}  = $mirrortime;
        $MIRROR_INFO{$host}->{'mtime'} = $now;
    }

    if ( open( my $mirror_speed_fh, '>', "$basedir/.cpcpan/mirrors.speeds" ) ) {
        print {$mirror_speed_fh} join( "\n", map { "$_=$MIRROR_INFO{$_}->{'speed'}=$MIRROR_INFO{$_}->{'time'}=$MIRROR_INFO{$_}->{'mtime'}" } keys %MIRROR_INFO ) . "\n";
        close($mirror_speed_fh);
    }
    else {
        die "Could not write: $basedir/.cpcpan/mirrors.speeds: $!";
    }

    foreach my $host ( sort { $MIRROR_INFO{$b}->{'speed'} <=> $MIRROR_INFO{$a}->{'speed'} } keys %MIRROR_INFO ) {
        next if ( $MIRROR_INFO{$host}->{'speed'} eq '0' || !exists $URLS{$host} );

        if ( $#GOODURLS == -1 ) {
            my $path = $URLS{$host};
            $path =~ s/http\:\/\/[^\/]+//g;
            my $valid      = '';
            my $goodmirror = 0;
            foreach my $doc ( '/index.html', '/modules/index.html' ) {
                eval { $valid = $httpClient->httpreq( $host, '/' . $path . $doc ); };
                if ( $valid =~ /perl/i || $valid =~ /cpan/i ) {
                    $goodmirror = $doc;
                    last;
                }
            }

            if ( $goodmirror eq '0' ) {
                print "Skipping Broken CPAN mirror $host\n";
                next;
            }
            else {
                print "Mirror Check passed for $host ($goodmirror)\n";
            }
        }
        push( @GOODURLS, $URLS{$host} );
    }

    if ( $#GOODURLS == -1 ) {
        unlink("$basedir/.cpcpan/mirrors.speeds");
        die "Ran out of working CPAN mirrors.  Please contact cPanel Support";
    }

    if ( open( my $good_urls_fh, '>', "$cpanbasedir/.cpcpan/goodurls" ) ) {
        print {$good_urls_fh} join( "\n", @GOODURLS );
        close($good_urls_fh);
    }

    return wantarray ? @GOODURLS : \@GOODURLS;
}

sub testmirrorspeed {
    my ( $host, $url, $rootmirroringfrom ) = @_;

    my $now = time();
    my $speed;

    # All urls are http now
    print "Testing connection speed to $host using pureperl...";
    require Cpanel::HttpTimer;
    my $RES = Cpanel::HttpTimer::timedrequest( 'url' => $url . 'MIRRORING.FROM', 'return_body' => 1, 'nolocal' => 1 );    # fix hang on cpan mirrors pointing to localhost
    $speed = $$RES{'speed'};

    my $mirroringfrom = get_epoch_seconds( $RES->{'body'} );

    if ( ( $mirroringfrom + ( 3 * 86400 ) ) < $rootmirroringfrom ) {
        $speed         = '';
        $mirroringfrom = $now;
        print "Warning: removing bad mirror $host from url list\n";

        #bad mirror -- more then 3 days out of date
    }
    if ( $speed eq '' ) {
        $speed = 0;
        print "test failed...Done\n";
    }
    else {
        print "($speed bytes/s)...Done\n";
    }

    return ( $speed, $mirroringfrom );
}

sub get_epoch_seconds {
    my ($epoch_str) = @_;
    my $eps;
    for ( split( /\n/, $epoch_str ) ) {
        if (/epoch\s*seconds\s*=\s*(\d+)/i) {
            $eps = $1;
            last;
        }
    }
    return $eps;
}

sub get_epoch_seconds_file {
    my ($epoch_file) = @_;
    my $epoch_str;

    if ( open( my $ts_fh, '<', $epoch_file ) ) {
        local $/ = undef;
        $epoch_str = <$ts_fh>;
        close($ts_fh);
    }

    return get_epoch_seconds($epoch_str);
}

sub _goodurls_ttl_ok {
    my $file  = shift;
    my $now   = shift;
    my $mtime = ( stat($file) )[9];
    if ( $mtime > $now )                   { return 0; }    #time warp
    if ( ( $mtime + $GOODURLTTL ) < $now ) { return 0; }
    return 1;
}

sub update_ping_times {
    my $url_ref   = shift;
    my $cpcpandir = "$basedir/.cpcpan/";
    my $my_mtime  = ( stat('/usr/local/cpanel/scripts/cpanpingtest') )[9];

    $| = 1;

    my $pingtimes_dir = $cpcpandir . 'pingtimes';
    if ( !-e $pingtimes_dir ) {
        mkdir $cpcpandir,     0700;
        mkdir $pingtimes_dir, 0700;
    }

    # Quick trip through the pingtimes directory to delete pingtimes files we won't use.
    opendir( my $dh, $pingtimes_dir );
    if ($dh) {
        my @oldpings = grep { !/^\.\.?$/ } readdir $dh;
        closedir $dh;

        # These hosts are not on our URL list
        @oldpings = grep { !exists $url_ref->{$_} } @oldpings;
        unlink map { "$pingtimes_dir/$_" } @oldpings;
    }

    my $now           = time();
    my $ping_file_ttl = ( 86400 * 20 );
    my @HOST_LIST;

    foreach my $host ( keys %{$url_ref} ) {
        my $ping_file_mtime = ( stat("$pingtimes_dir/$host") )[9];
        if ( $ping_file_mtime && $ping_file_mtime > $my_mtime && ( $ping_file_mtime + $ping_file_ttl ) > $now ) {
            next;
        }
        push @HOST_LIST, $host;

    }

    if (@HOST_LIST) {
        system( '/usr/local/cpanel/scripts/cpanpingtest', @HOST_LIST );
    }
}

1;
