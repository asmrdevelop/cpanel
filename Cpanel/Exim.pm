package Cpanel::Exim;

# cpanel - Cpanel/Exim.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(RequireUseWarnings) - needs audit

use Cpanel::CachedCommand      ();
use Cpanel::Config::LoadCpConf ();
use Cpanel::Config::LoadConfig ();
use Cpanel::Binaries           ();
use Cpanel::Version::Compare   ();

our $EXISCAN_DISABLE_FLAG_FILE = '/etc/exiscandisable';

sub _fetch_eximconf {
    return Cpanel::Config::LoadConfig::loadConfig( '/etc/exim.conf.localopts', undef, '=' );
}

sub fetch_caps {
    my $cpconf   = Cpanel::Config::LoadCpConf::loadcpconf();
    my $eximconf = _fetch_eximconf();

    my ( $eximbin, $eximversion, $hasdkim, $hasspf, $dovecot, $haspasswd, $has_content_scanning, $hasdomainkeys, $directives ) = geteximinfo();

    require Cpanel::AdvConfig::dovecot;
    my $dovecot_conf_hr = Cpanel::AdvConfig::dovecot::get_config();

    my %EXIM_CAP = (
        'add_header'                        => 0,
        'notquit'                           => 0,
        'spf'                               => int $hasspf,
        'maildir'                           => 1,
        'exiscan'                           => 0,
        'mailman'                           => 0,
        'content_scanning'                  => $has_content_scanning,
        'domainkeys'                        => int $hasdomainkeys,
        'dkim'                              => int $hasdkim,
        'passwd'                            => int $haspasswd,
        'archive'                           => ( $cpconf->{'emailarchive'}                                                                               ? 1 : 0 ),
        'boxtrapper'                        => ( $cpconf->{'skipboxtrapper'}                                                                             ? 0 : 1 ),
        'rewrite_from_remote'               => ( ( defined $eximconf->{'rewrite_from'} && $eximconf->{'rewrite_from'} eq 'remote' )                      ? 1 : 0 ),
        'rewrite_from_all'                  => ( ( defined $eximconf->{'rewrite_from'} && $eximconf->{'rewrite_from'} eq 'all' )                         ? 1 : 0 ),
        'no_forward_outbound_spam'          => ( $eximconf->{'no_forward_outbound_spam'}                                                                 ? 1 : 0 ),
        'no_forward_outbound_spam_over_int' => ( $eximconf->{'no_forward_outbound_spam_over_int'}                                                        ? 1 : 0 ),
        'reject_overquota_at_smtp_time'     => ( $dovecot_conf_hr->{'incoming_reached_quota'} && $dovecot_conf_hr->{'incoming_reached_quota'} eq 'defer' ? 0 : 1 ),
        'srs'                               => ( $eximconf->{'srs'}                                                                                      ? 1 : 0 ),
        'dovecot'                           => 1,
        'directives'                        => $directives,
    );
    if ( Cpanel::Version::Compare::compare( $eximversion, '<', 4.62 ) ) {
        print_warning("you are running an old version of exim that has known problems.  You should update to exim 4.62 or later as soon as possible.");
    }
    elsif ( Cpanel::Version::Compare::compare( $eximversion, '<', 4.68 ) ) {
        print_warning("you are running an old version of exim that cannot fight spam as well as newer versions.  You should update to exim 4.68 or later as soon as possible.");
        $EXIM_CAP{'add_header'} = 1;
    }
    else {
        $EXIM_CAP{'add_header'} = 1;
        $EXIM_CAP{'notquit'}    = 1;
    }
    if ( !$cpconf->{'skipmailman'} && ( getpwnam('mailman') )[0] ) {
        $EXIM_CAP{'mailman'} = 1;
    }

    # Clam AV is RPM controlled now, so we just need to make sure the binary is there and executable
    my $clamd_path = Cpanel::Binaries::path("clamd");
    if ( -x $clamd_path && !-e $EXISCAN_DISABLE_FLAG_FILE ) {
        $EXIM_CAP{'exiscan'} = 1;
    }

    $EXIM_CAP{'force_command'} = _test_for_force_command( { 'eximbin' => $eximbin, 'eximversion' => $eximversion, 'exim_caps' => \%EXIM_CAP } );

    return ( $eximbin, $eximversion, \%EXIM_CAP );

}

sub find_exim {
    return geteximinfo(1);
}

sub _test_for_force_command {
    my ($self) = @_;

    my $grep_output = Cpanel::CachedCommand::cachedcommand_multifile(
        [ $self->{'eximbin'} ],
        '/bin/grep',
        'force_command',
        $self->{'eximbin'},
    );
    return $grep_output ? 1 : 0;
}

sub geteximinfo {
    my $binonly = shift;
    my $eximbin = Cpanel::Binaries::path('exim');
    if ( !-x $eximbin ) {
        $eximbin = Cpanel::Binaries::path('sendmail');
    }
    if ($binonly) { return $eximbin; }
    if ( !-x $eximbin ) {
        die 'Exim binary not found!';
    }

    my $hasdkim              = 0;
    my $has_content_scanning = 0;
    my $hasspf               = 0;
    my $hasdovecot           = 0;
    my $haspasswd            = 0;
    my $hasdomainkeys        = 0;
    my $eximFversion         = Cpanel::CachedCommand::cachedcommand( $eximbin, '-bV' );

    $eximFversion =~ m/version\s+([\d\.]+)/;
    my $eximver = $1;
    if ( !$eximver ) {
        die "Invalid or broken exim binary: exim -bV returned: $eximFversion\n";
    }
    if ( $eximFversion =~ m/dkim/i && $eximFversion !~ m/Experimental_DKIM/i ) {    #Experimental_DKIM does not have the dkim acl
        $hasdkim = 1;
    }
    if ( $eximFversion =~ m/Content_Scanning/i ) {
        $has_content_scanning = 1;
    }
    if ( $eximFversion =~ m/spf/i ) {
        $hasspf = 1;
    }
    if ( $eximFversion =~ m/domainkeys/i ) {
        $hasdomainkeys = 1;
    }
    if ( $eximFversion =~ m/Authenticators:.*dovecot/i ) {
        $hasdovecot = 1;
    }

    #Lookups (built-in): lsearch wildlsearch nwildlsearch iplsearch dbm dbmnz passwd
    if ( $eximFversion =~ m/^\s*Lookups[^\:]*:.*passwd/mi ) {
        $haspasswd = 1;
    }

    my $null_conf = Cpanel::CachedCommand::cachedcommand( $eximbin, '-C/dev/null', '-bP' );
    my %directives;
    while ( $null_conf =~ /^(\S+)/mg ) {
        my $directive = $1;
        $directive =~ s/^no_//;
        $directives{$directive} = 1;
    }
    return ( $eximbin, $eximver, $hasdkim, $hasspf, $hasdovecot, $haspasswd, $has_content_scanning, $hasdomainkeys, \%directives );
}

sub print_warning {
    my $warning = shift;
    print "@!" x 40 . "\n";
    print "Warning, $warning\n.";
    print "@!" x 40 . "\n";
}

sub fetch_config_template_name {
    return 'dist';
}

1;
