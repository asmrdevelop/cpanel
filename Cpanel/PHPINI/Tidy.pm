package Cpanel::PHPINI::Tidy;

# cpanel - Cpanel/PHPINI/Tidy.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use IO::Handle                   ();
use Cpanel::FileUtils::Write     ();
use Cpanel::SafeRun::Simple      ();
use Cpanel::SafeFile             ();
use Cpanel::PHPConfig::Locations ();

our $VERSION = 1.1;
our $QUIET   = 0;

sub phpini_tidy {
    my %LOCATIONS = Cpanel::PHPConfig::Locations::get_php_locations();
    foreach my $location ( keys %LOCATIONS ) {
        my $php_ini = get_php_ini_location( $LOCATIONS{$location}->{'php'} );
        if ($php_ini) {
            print "Tidying $php_ini...\n" unless $QUIET;
            tidy_phpini_file($php_ini);
        }
        else {
            print "$LOCATIONS{$location}->{'php'} does not have a php.ini\n" unless $QUIET;
        }
    }
}

sub tidy_phpini_file {
    my $php_ini = shift;
    my $inifh   = IO::Handle->new();
    if ( my $inilock = Cpanel::SafeFile::safeopen( $inifh, '+<', $php_ini ) ) {
        my %SEEN_EXTS;
        my $modified = 0;
        my @newini;
        while ( my $line = readline($inifh) ) {
            if ( $line =~ m/^\s*extension\s*=\s*[\"\']?\s*([^"']+)/ ) {
                my $ext = $1;
                $ext =~ s/[\r\n]//g;
                $ext =~ s/\s*//g;
                if ( $SEEN_EXTS{$ext} ) {
                    $modified = 1;
                    print "\tSkipping duplicate extension: $ext\n" unless $QUIET;
                    next;
                }

                $SEEN_EXTS{$ext} = 1;
            }
            push @newini, $line;
        }
        if ($modified) {
            Cpanel::FileUtils::Write::write_fh( $inifh, join( '', @newini ) );
            print "Wrote changes\n" unless $QUIET;
        }
        else {
            print "No changes\n" unless $QUIET;
        }

        Cpanel::SafeFile::safeclose( $inifh, $inilock );
        return 1;
    }
    return 0;
}

sub get_php_ini_location {
    my $php_bin = shift;
    my $php_ini;

    foreach my $line ( split( m/\n/, scalar Cpanel::SafeRun::Simple::saferun( $php_bin, '-i' ) ) ) {
        $line =~ s{ < \W* \w+ [^>]* > }{}xmsg;
        if ( $line =~ m/\s+(\/\S+\/php\.ini)/ ) {
            $php_ini = $1;
            last;
        }

    }
    return $php_ini;
}

1;
