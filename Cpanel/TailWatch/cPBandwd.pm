package Cpanel::TailWatch::cPBandwd;

# cpanel - Cpanel/TailWatch/cPBandwd.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Cpanel::TailWatch::Base';
use Cpanel::OS ();

#############################################################
# no other use()s, require() only *and* only then in init() #
#############################################################

# /usr/local/cpanel already in @INC
# should work with these on but disabled in production for slight memory gain
# use strict;
# use warnings;
# use vars qw($VERSION);
our $VERSION = 0.3;

my $FH                                   = 0;
my $NUM_WRITES                           = 1;
my $MAX_OPEN_LOG_FILES                   = 384;
my $cpanellogd_supports_opened_byteslogs = 1;
my $apacheconf;

# Should not be changed. Provided as a modification point for testing.
#NOTE: This duplicates Cpanel::ConfigFiles::Apache::dir_domlogs()
our $_domlogdir = '/usr/local/apache/domlogs';

#############################################################
# no other use()s, require() only *and* only then in init() #
#############################################################

sub init {

    # this is where modules should be require()'d
    # this method gets called if PKG->is_enabled()

    require Time::Local;
    require Cpanel::ConfigFiles::Apache;
    require Cpanel::TailWatch;

    $apacheconf = Cpanel::ConfigFiles::Apache->new();
    $_domlogdir = $apacheconf->dir_domlogs();
}

sub internal_name { return 'cpbandwd'; }

sub new {
    my ( $my_ns, $tailwatch_obj ) = @_;
    my $self = bless { 'internal_store' => {} }, $my_ns;

    $self->{'internal_store'}{'domlogsdir'} = $_domlogdir;
    if ( !-e $self->{'internal_store'}{'domlogsdir'} ) {
        mkdir $self->{'internal_store'}{'domlogsdir'}, 0755;
    }

    my $maillog = Cpanel::OS::maillog_path();
    $maillog = $maillog . '.0' if !-f $maillog;
    $maillog = '/var/log/mail' if !-f $maillog;

    $tailwatch_obj->register_module( $self, __PACKAGE__, Cpanel::TailWatch::PREVPNT(), [$maillog] );

    $self->{'process_line_regex'}->{$maillog} = qr/dovecot(\[\d+\])?:.*bytes/;

    return $self;
}

sub get_user_and_domain {
    my ($user_domain) = @_;

    return ($user_domain) unless $user_domain =~ tr/\@\%:+//;

    return ( $1, $2 ) if $user_domain =~ m/^([^\@]+)\@(\S+)$/;
    return ( $1, $2 ) if $user_domain =~ m/^([^\%:+]+)[\%:+](\S+)$/;

    return ($user_domain);
}

sub _user_exists {
    my ($user) = @_;

    return scalar( getpwnam($user) );
}

sub process_line {    ## no critic(Subroutines::ProhibitExcessComplexity)
    my ( $self, $line, $tailwatch_obj ) = @_;

    # Exclude creation of bytes log for cPanel Service Auth requests
    return if $line =~ m/__cpanel__service__auth__/;

    my $entries_ref = {};

    my $bytes  = 0;
    my $domain = '';
    my $user   = '';
    my $type   = '';
    my ( $ident, $message ) = split( /:\s+/, $line, 2 );
    if ( $ident =~ /\sdovecot(?:\z|\[\d+\])/ && $message =~ /\A(pop3|imap)\(([^)]+)\).*?:.*\s+bytes\s*=\s*\d+\/(\d+)\Z/i ) {

        $type = lc $1;
        if ( $type eq 'imap' ) {
            $type = 'imapd';
        }

        $user  = $2;
        $bytes = $3;

        ( $user, $domain ) = get_user_and_domain($user);
    }
    return if !$bytes;

    my $bytes_user;

    if ( $domain && ( $domain ne $tailwatch_obj->{'global_share'}{'data_cache'}{'hostname'} ) ) {

        # If we have a domain, lookup according to the userdomains map.
        $bytes_user = $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}->{$domain};
    }
    elsif ( _user_exists($user) ) {

        # Otherwise, make sure the user we were given is valid, and use that.
        $bytes_user = $user;
    }

    # Bail out if we don't have a valid user.
    # Otherwise we may be subject to path manipulation attacks.
    # See Case 112361.
    return if !$bytes_user;

    my $bytesfile = $self->{'internal_store'}{'domlogsdir'} . '/' . $bytes_user . ( $type eq 'pop3' ? '-popbytes_log' : '-imapbytes_log' );

    #print "LINE: $line\n";
    #print "User: $user\n";
    #print "\t--> BYTES: $bytes\n";

    # get date
    my %monthlookup = (
        'jan' => 0,
        'feb' => 1,
        'mar' => 2,
        'apr' => 3,
        'may' => 4,
        'jun' => 5,
        'jul' => 6,
        'aug' => 7,
        'sep' => 8,
        'oct' => 9,
        'nov' => 10,
        'dec' => 11,
    );

    my ( $now_day, $now_month, $now_year ) = (localtime)[ 3, 4, 5 ];
    $now_year += 1900;
    my ( $month, $day, $hour, $min, $sec );
    my $time;

    if ( $line =~ m{ \A ([A-Za-z]+) \s+ (\d+) \s (\d+) [:] (\d+) [:] (\d+) }xms ) {
        $month = lc $1;
        $day   = $2;
        $hour  = $3;
        $min   = $4;
        $sec   = $5;

        if ( exists $monthlookup{$month} ) {
            $month = $monthlookup{$month};
        }
        else {
            foreach my $month_string ( keys %monthlookup ) {
                if ( substr( $month, 3, 0 ) eq $month_string ) {
                    $month = $monthlookup{$month_string};
                    last;
                }
            }
            if ( !$month ) {
                warn "Problem determining month.\n";
                $month = $now_month;
            }
        }

        #print "Month: $month NOW: $now_month\n";

        # determine year
        if ( $month > $now_month ) {
            $now_year = $now_year - 1;
        }
    }
    else {
        $time = time;
    }

    $time ||= int eval { Time::Local::timelocal( $sec, $min, $hour, $day, $month, $now_year ) } || time();

    #print "\tEntry time: $time\n";

    $tailwatch_obj->debug("Appending the line '$time $bytes .' to $bytesfile") if $tailwatch_obj->{'debug'};

    if ( !-e $bytesfile || !exists $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$bytesfile} || !$tailwatch_obj->{'global_share'}->{'open_log_files'}->{$bytesfile}->[$FH] ) {

        #
        # No reason to use file locking here since order does not matter
        # we use a syswrite to ensure buffering does not cause a partial write
        #
        while ( scalar keys %{ $tailwatch_obj->{'global_share'}->{'open_log_files'} } >= $MAX_OPEN_LOG_FILES ) {
            my $least_used_key = ( sort { $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$a}->[$NUM_WRITES] <=> $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$b}->[$NUM_WRITES] } keys %{ $tailwatch_obj->{'global_share'}->{'open_log_files'} } )[0];
            close( $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$least_used_key}->[$FH] );
            delete $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$least_used_key};
        }

        if ( open( $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$bytesfile}->[$FH], '>>', $bytesfile ) ) {
            $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$bytesfile}->[$NUM_WRITES] = 0;
        }
        else {
            $tailwatch_obj->log("Failed to open $bytesfile: $!");
        }
    }

    if ( $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$bytesfile}->[$FH] ) {
        $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$bytesfile}->[$NUM_WRITES]++;
        syswrite( $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$bytesfile}->[$FH], $time . ' ' . $bytes . " .\n" );
        unless ($cpanellogd_supports_opened_byteslogs) {
            close( $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$bytesfile}->[$FH] );
            delete $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$bytesfile};
        }
    }
    else {
        $tailwatch_obj->log("Failed to write bytes_log data to $bytesfile (File could not be opened: $!)");
    }

    return;
}

sub flush {
    my ( $self, $tailwatch_obj ) = @_;

    foreach my $bytesfile ( keys %{ $tailwatch_obj->{'global_share'}->{'open_log_files'} } ) {
        next unless $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$bytesfile}->[$FH];
        close( $tailwatch_obj->{'global_share'}->{'open_log_files'}->{$bytesfile}->[$FH] );
    }
    return;
}

## Driver specific helpers ##

1;
