package Cpanel::MirrorSearch;

# cpanel - Cpanel/MirrorSearch.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::HttpTimer ();
use IO::Handle        ();

# FIXME: use perl pipe instead of OSSys
use Carp ();

our $VERSION = '2.2';

sub remove_mirror {
    my %REQ  = @_;
    my $key  = $REQ{'key'};
    my $addr = $REQ{'addr'};
    $key  =~ s/\///g;
    $addr =~ s/\///g;

    my $homedir = ( getpwuid($>) )[7];
    unlink("$homedir/.MirrorSearch/$key/pingtimes/$addr");
    if ( open( my $mspeeds_fh, '+<', "$homedir/.MirrorSearch/$key/mirrors.speeds" ) ) {
        my @mspeeds = grep( !/^\Q$addr\E=/, <$mspeeds_fh> );
        seek( $mspeeds_fh, 0, 0 );
        print {$mspeeds_fh} join( '', @mspeeds );
        truncate( $mspeeds_fh, tell($mspeeds_fh) );
        close($mspeeds_fh);
    }
}

sub findfastest {
    my (%REQ) = @_;

    my $now     = time();
    my $days    = $REQ{'days'};
    my $key     = $REQ{'key'};
    my $count   = $REQ{'count'};
    my @urls    = @{ $REQ{'urls'} };
    my $urllist = join( "\n", @urls );

    die 'You must specify the number of days to cache a host speed (days)' if ( $days eq '' );
    die 'You must specify a key to use for this host (key)'                if ( $key eq '' );
    die 'You must specify a number of hosts to return (count)'             if ( $count eq '' );
    die 'You must specify an array of urls to try (urls)'                  if ( $urllist eq '' );

    $key =~ s/\///g;

    my %URLS;
    foreach my $url (@urls) {
        if ( $url =~ /(?:ftp|http)\:\/\/([^\/]+)\// ) {
            my $host = $1;
            $URLS{$host} = $url;
        }
        else {
            Carp::confess 'Invalid Url';
        }
    }

    #Try to see if we can load it from cache
    my @GOODURLS = _fetchgoodhosts( $key, $REQ{'port'}, $days, $count, {}, \%URLS, 1, $REQ{'port'} );
    if ( $#GOODURLS >= ( $count - 1 ) ) {

        #we have enough good ones in the cache already
        if ( !$REQ{'quiet'} ) { print "...loaded mirror speeds from cache..."; }
        return @GOODURLS;
    }

    #Loading from cache failed so lets go though the whole process
    my %PINGTIMES;
    my $homedir = ( getpwuid($>) )[7];

    mkdir $homedir . '/.MirrorSearch',         0700 if !-e $homedir . '/.MirrorSearch';
    mkdir $homedir . '/.MirrorSearch/' . $key, 0700 if !-e $homedir . '/.MirrorSearch/' . $key;

    my $need_pings = 0;
    foreach my $host ( keys %URLS ) {
        my $cache_mtime = ( stat("$homedir/.MirrorSearch/${key}/pingtimes/${host}") )[9] || 0;
        next if ( ( $cache_mtime + ( 86400 * $days ) ) > $now );
        $need_pings++;
        $PINGTIMES{$host} = 1000;    #if ping is broken
    }

    if ($need_pings) {
        local $^F = 1000;            #prevent cloexec on pipe
        my $read_fd  = IO::Handle->new();
        my $write_fd = IO::Handle->new();
        pipe( $read_fd, $write_fd );
        syswrite( $write_fd, $urllist );
        close($write_fd);

        if ( $REQ{'quiet'} ) {
            require Cpanel::SafeRun::Errors;
            Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/MirrorSearch_pingtest', $key, $days, fileno $read_fd, $REQ{'port'} );
        }
        else {
            print "Testing connection speed for $key ($need_pings servers)...(using fast method)...";
            system '/usr/local/cpanel/scripts/MirrorSearch_pingtest', $key, $days, fileno $read_fd, $REQ{'port'};
            print ".Done\n";
        }
        close($read_fd);
    }

    # load the ping time
    opendir( PT, "$homedir/.MirrorSearch/${key}/pingtimes" );
    while ( my $pt = readdir(PT) ) {
        next if ( $pt =~ /^\./ );
        open( my $pingtimes_fh, '<', "$homedir/.MirrorSearch/$key/pingtimes/$pt" );
        $PINGTIMES{$pt} = <$pingtimes_fh>;
        chomp $PINGTIMES{$pt};
        close($pingtimes_fh);
    }
    closedir(PT);

    return _fetchgoodhosts( $key, $REQ{'port'}, $days, $count, \%PINGTIMES, \%URLS, 0, $REQ{'quiet'} );
}

sub _fetchgoodhosts {
    my $key       = shift;
    my $port      = shift;
    my $days      = shift;
    my $count     = shift;
    my $PINGTIMES = shift;
    my $URLS      = shift;
    my $cacheonly = shift;
    my $quiet     = shift || 0;

    $key =~ s/\///g;
    my $now = time();
    my %MIRRORSPEED;
    my %MIRRORTIME;
    my @GOODURLS;

    my $homedir = ( getpwuid($>) )[7];
    if ( open my $mirrorspeeds_fh, '<', "$homedir/.MirrorSearch/${key}/mirrors.speeds" ) {
        while (<$mirrorspeeds_fh>) {
            chomp;
            my ( $mirror, $speed, $lastcheck ) = split( /=/, $_ );

            next if ( $lastcheck < ( $now - ( 86400 * $days ) ) );

            $MIRRORTIME{$mirror}  = $lastcheck;
            $MIRRORSPEED{$mirror} = $speed;
        }
        close $mirrorspeeds_fh;
    }
    if ($cacheonly) {
        foreach my $host ( sort { $MIRRORSPEED{$b} <=> $MIRRORSPEED{$a} } keys %MIRRORSPEED ) {
            push( @GOODURLS, $$URLS{$host} ) if $$URLS{$host};
        }
    }
    else {
        my $usable_mirror_count = 0;
        my %URLS_BY_SPEED;
        foreach my $host ( sort { $$PINGTIMES{$a} <=> $$PINGTIMES{$b} } keys %{$PINGTIMES} ) {
            if ( $$URLS{$host} ) {
                if ( !defined $MIRRORSPEED{$host} || $MIRRORSPEED{$host} eq '' ) {
                    print "Ping:$$PINGTIMES{$host} (seconds) " if !$quiet;
                    ( $MIRRORSPEED{$host} ) = _testmirrorspeed( $$URLS{$host}, $quiet, $port );
                    $MIRRORTIME{$host} = $now;
                }

                if ( $MIRRORSPEED{$host} > 1 ) {
                    $URLS_BY_SPEED{ $$URLS{$host} } = $MIRRORSPEED{$host};
                    if ( ++$usable_mirror_count >= $count ) {
                        print "$count usable mirrors located\n" if !$quiet;
                        last;
                    }
                }
            }
        }

        if ( $usable_mirror_count < $count ) { print "...$usable_mirror_count usable mirrors located. (less then expected)..." if !$quiet; }

        # Load up the urls into the array by order of speed
        @GOODURLS = sort { $URLS_BY_SPEED{$b} <=> $URLS_BY_SPEED{$a} } keys %URLS_BY_SPEED;

        if ($usable_mirror_count) {    # dump the cache so we retry next time around
            if ( open my $mirrorspeeds_fh, '>', "$homedir/.MirrorSearch/${key}/mirrors.speeds" ) {
                foreach my $mirror ( keys %MIRRORSPEED ) {
                    print {$mirrorspeeds_fh} "${mirror}=$MIRRORSPEED{$mirror}=$MIRRORTIME{$mirror}\n";
                }
                close $mirrorspeeds_fh;
            }
            else {
                warn "Unable to write $homedir/.MirrorSearch/${key}/mirrors.speeds: $!";
            }
        }
        else {
            unlink("$homedir/.MirrorSearch/$key/mirrors.speeds");
        }
    }
    return @GOODURLS;
}

sub _testmirrorspeed {
    my ( $url, $quiet, $port ) = @_;

    my ($host) = $url =~ /(?:ftp|http)\:\/\/([^\/]+)\//;

    Carp::confess( 'Invalid Url : ' . $url ) if !$host;

    print "Testing connection speed to $host using pureperl..." if !$quiet;
    my $RES = Cpanel::HttpTimer::timedrequest( 'url' => $url, 'port' => $port, 'nolocal' => 1, 'quiet' => 1 );    # fix hang on mirrors pointing to localhost
    if ( !$RES->{'speed'} ) {
        print "test failed...Done\n" if !$quiet;
        return 0;
    }
    else {
        print "($RES->{'speed'} bytes/s)...Done\n" if !$quiet;
        return $RES->{'speed'};
    }
}

1;
