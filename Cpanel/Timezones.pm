package Cpanel::Timezones;

# cpanel - Cpanel/Timezones.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS    ();
use Cpanel::Debug ();
use Cpanel::SafeRun::Errors();

use Cwd        ();
use List::Util ();

use constant _ENOENT => 2;

our $timezones_cachefile = '/var/cpanel/timezones.cache';
my $cache_ttl = 3_600 * 24 * 7 * 6;    #6 WEEKS

our $timezones_cache;

our $timezonedir   = '/usr/share/zoneinfo';
our $zonetabfile   = '/usr/share/zoneinfo/zone.tab';
our $etc_localtime = '/etc/localtime';

sub gettimezones() {
    if ( !$timezones_cache ) {
        my $timezones;

        if ( open my $fh, '<', $timezones_cachefile ) {
            $timezones = -f $fh;
            $timezones &&= ( time - ( stat $fh )[9] ) < $cache_ttl;

            $timezones &&= [<$fh>];
            chomp @$timezones if $timezones;
        }
        elsif ( $! != _ENOENT ) {
            warn "open($timezones_cachefile): $!";
        }

        if ( !$timezones || !scalar @{$timezones} || !grep { $_ eq "UTC" } @$timezones ) {
            $timezones = [];
            get_timezones_from_zonetab($timezones);

            if ( !scalar @{$timezones} ) {
                require Cpanel::FileUtils::Lines;
                require File::Find;
                File::Find::find(
                    sub {
                        if ( Cpanel::FileUtils::Lines::has_txt_in_file( $File::Find::name, '\ATZif' ) ) {
                            ( my $stripped_name = $File::Find::name ) =~ s{\A$timezonedir/}{};
                            push @{$timezones}, $stripped_name;
                        }
                    },
                    $timezonedir
                );
            }
            push @$timezones, "UTC" unless grep { $_ eq "UTC" } @$timezones;

            if ( _running_as_root() ) {
                require Cpanel::FileUtils::Write;
                Cpanel::FileUtils::Write::overwrite_no_exceptions( $timezones_cachefile, join( "\n", @{$timezones} ), 0644 );
            }
        }

        $timezones_cache = $timezones;
    }

    return wantarray ? @$timezones_cache : $timezones_cache;
}

sub _running_as_root {
    return $> == 0 ? 1 : 0;
}

sub is_valid ($tz) {
    my $is_valid;

    require Cpanel::FileUtils::Lines;
    if ($timezones_cache) {
        $is_valid = grep { $_ eq $tz } @$timezones_cache;
    }
    elsif ( -f $timezones_cachefile && ( time() - ( stat $timezones_cachefile )[9] <= $cache_ttl ) ) {

        #THIS REGEX USES \Z, NOT \z, BECAUSE has_txt_in_file DOESN'T chomp.
        $is_valid = Cpanel::FileUtils::Lines::has_txt_in_file( $timezones_cachefile, qr(\A\Q$tz\E\Z) );
    }
    else {
        $is_valid = grep { $_ eq $tz } ( gettimezones() );
    }

    return $is_valid;
}

sub set ($tz) {

    return unless is_valid($tz);

    # Cpanel::OS provides the method to use to setup the timezone
    #            so we do not have to guess which one to use
    my $method = Cpanel::OS::setup_tz_method();

    if ( $method eq 'timedatectl' ) {
        _setup_clock_using_timedatectl($tz);
    }
    elsif ( $method eq 'sysconfig' ) {
        _setup_clock_using_sysconfig($tz);
    }
    else {
        Cpanel::Debug::log_die("Invalid setup_tz_method method: $method");
    }

    return;
}

sub _get_active_timezone {
    my @tz_data = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/bin/timedatectl', 'show' );

    my ( undef, $tz_name ) = split( q{=}, List::Util::first { /^timezone=/i } @tz_data );

    return $tz_name;
}

sub _setup_clock_using_timedatectl ($tz) {

    Cpanel::SafeRun::Errors::saferunallerrors( '/usr/bin/timedatectl', 'set-timezone', $tz );

    return;
}

sub _setup_clock_using_sysconfig ($tz) {

    my @CLOCK;

    if ( open( my $fh, '<', '/etc/sysconfig/clock' ) ) {
        @CLOCK = (<$fh>);
        close($fh);
    }
    else {
        Cpanel::Debug::log_warn(qq[Could not open file "/etc/sysconfig/clock" for reading ($!)]);
    }

    if ( open( my $fh, '>', '/etc/sysconfig/clock' ) ) {
        my $ok;
        foreach my $line (@CLOCK) {
            if ( $line =~ m{\AZONE=}i ) {
                $ok = 1;
                print {$fh} qq[ZONE="$tz"\n];
            }
            else {
                print {$fh} $line;
            }
        }
        print {$fh} qq[ZONE="$tz"\n] unless $ok;
        close($fh);

        unlink $etc_localtime;
        symlink "/usr/share/zoneinfo/$tz", $etc_localtime;

    }
    else {
        Cpanel::Debug::log_warn(qq[Could not open file "/etc/sysconfig/clock" for writing ($!)]);
    }

    return;
}

sub get_timezones_from_zonetab ($timezones_ar) {

    my $fh;
    if ( !open $fh, '<', $zonetabfile ) {
        Cpanel::Debug::log_warn("Could not open file \"$zonetabfile\" for reading ($!), will attempt to determine the time zone list by other (probably less precise) method(s)");
        return;
    }

    while (<$fh>) {
        next unless m{ ^ [A-Z]+ \s+ [-+][-+\d]+ \s+ (\S+) }ax;
        push @{$timezones_ar}, $1;
    }

    close $fh;

    return 1;
}

sub _hash_file ($file) {

    require Digest::SHA;
    return Digest::SHA->new(512)->addfile($file)->hexdigest;
}

sub get_current_timezone (%opts) {

    my $tz = 'UTC';    # default value when none found

    if ( -l $etc_localtime ) {    # check file being symlinked, if symlinked
        $tz = Cwd::abs_path($etc_localtime);
        $tz =~ s{^.*/usr/share/zoneinfo/(?:Etc/)?}{};
    }
    elsif ( -f $etc_localtime ) {

        # find out which timezone file was copied by matching hash (could be several, take first)
        my $localhash = _hash_file($etc_localtime);
        my @TZS       = gettimezones();
        foreach my $tzfile (@TZS) {
            my $check = $timezonedir . '/' . $tzfile;
            next unless -f $check;
            my $digest = _hash_file($check);
            if ( $localhash eq $digest ) {
                $tz = $tzfile;
                last;
            }
        }
    }
    else {
        # Get the timezone data from timedatectl if /etc/localtime is absent.
        $tz = _get_active_timezone();

        my $tz_file_path = qq{$timezonedir/$tz};

        # Attempt to rebuild /etc/localtime if running as root.
        if ( defined $tz && -e $tz_file_path && $> == 0 ) {
            symlink( $tz_file_path, $etc_localtime );
            Cpanel::Timezones::set($tz);
        }
    }

    $tz =~ s{^posix/}{} if $opts{noposix};

    return $tz;
}

sub calculate_TZ_env() {
    return get_current_timezone( noposix => 1 );
}

sub set_zonetabfile ($file) {
    $zonetabfile = $file;
    return;
}

sub clear_caches() {
    undef $timezones_cache;
    unlink $timezones_cachefile;

    return;
}

1;
