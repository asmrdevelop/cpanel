package Cpanel::ServiceManager::Services::Spamd;

# cpanel - Cpanel/ServiceManager/Services/Spamd.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::ServiceManager::Base ();
extends 'Cpanel::ServiceManager::Base';

use IO::Handle                      ();
use Cpanel::FastSpawn::InOut        ();
use Cpanel::Binaries                ();
use Cpanel::Exception               ();
use Cpanel::PwCache                 ();
use Cpanel::FileUtils::TouchFile    ();
use Cpanel::ChildErrorStringifier   ();
use Cpanel::Services::Enabled       ();
use Cpanel::SpamAssassin::Constants ();

has '+service_package' => ( is => 'ro', lazy => 1, default => sub { 'cpanel-perl-' . Cpanel::Binaries::PERL_MAJOR . '-Mail-SpamAssassin' } );
has '+doomed_rules'    => ( is => 'ro', lazy => 1, default => sub { [ 'spamd', 'spamd -d' ] } );
has '+ports'           => ( is => 'ro', lazy => 1, default => sub { [783] } );
has '+startup_args'    => ( is => 'ro', lazy => 1, default => \&_getspamdopts );

has '+is_cpanel_service' => ( is => 'ro', default => 1 );
has '+pidfile'           => ( is => 'ro', default => '/var/run/spamd.pid' );

# this is a wrapper to start spamd in dormant mode if enabled libexec-dnsadmin-dormant
has '+service_binary'      => ( is => 'ro', default => '/usr/local/cpanel/libexec/spamd-startup' );
has '+restart_attempts'    => ( is => 'ro', default => 2 );
has '+block_fresh_install' => ( is => 'ro', default => 1 );
has '+is_enabled'          => ( is => 'rw', lazy    => 1, builder => 1 );

our $CONFIG_FILE = '/etc/cpspamd.conf';

# We use the parent class to set is_enabled. But we need behavior based on its value.
# This seems to be the only way to hook into that at startup.
sub _build_is_enabled {
    my ($self) = @_;

    return 0 unless $self->SUPER::_build_is_enabled();

    Cpanel::FileUtils::TouchFile::touchfile($CONFIG_FILE) unless -e $CONFIG_FILE;

    return 1;
}

sub restart_attempt {
    my ( $self, $retry_attempt ) = @_;

    # when failing to start spamd with spamd-startup, switch to the regular binary
    if ( $retry_attempt == 1 ) {
        my $main_bin = Cpanel::Binaries::path( lc( $self->service() ) );
        $self->logger()->info( q{The service '} . $self->service() . qq{' failed to restart. Trying '$main_bin'.} );
        $self->service_binary($main_bin);
    }

    return 1;
}

sub _getspamdopts {
    my $cpspamdconf  = $CONFIG_FILE;
    my @spamdoptions = qw(--daemonize);
    my @allowedips;
    if ( -e $cpspamdconf ) {
        my $fh = IO::Handle->new();
        open( $fh, "<", $cpspamdconf ) or die $!;
        while (<$fh>) {
            if ( !(/^[\s\t]*$/) && !(/^[\s\t]*\#.*$/) ) {
                chomp();
                my ( $option, $value ) = split( '=', $_ );
                next if ( !defined $value || $value eq '' );
                if ( $option eq 'allowedips' ) {
                    push @allowedips, split( /\s*,\s*/, $value );
                }
                elsif ( $option eq 'socketpath' ) {
                    push @spamdoptions, "--socketpath=${value}";
                }
                elsif ( $option eq 'maxconnperchild' ) {
                    push @spamdoptions, "--max-conn-per-child=${value}";
                }
                elsif ( $option eq 'maxspare' ) {
                    push @spamdoptions, "--max-spare=${value}";
                }
                elsif ( $option eq 'maxchildren' ) {
                    push @spamdoptions, "--max-children=${value}";
                }
                elsif ( $option eq 'pidfile' ) {
                    push @spamdoptions, "--pidfile=${value}";
                }
                elsif ( $option eq 'local' ) {
                    push @spamdoptions, '--local';
                }
                elsif ( $option eq 'timeouttcp' ) {
                    push @spamdoptions, "--timeout-tcp=${value}";
                }
                elsif ( $option eq 'timeoutchild' ) {
                    push @spamdoptions, "--timeout-child=${value}";
                }
            }
        }
        close($fh);
    }

    {
        # always allow localhost ips (or this breack chkservd and more)
        push @allowedips, q{127.0.0.1}, q{::1};
        my %h_allowedips = map { $_ => 1 } @allowedips;    # lazy uniq
        push @spamdoptions, '--allowed-ips=' . join( ',', sort keys %h_allowedips );
    }

    push @spamdoptions, '--max-children=5'
      if !grep { m/^--max-children/ } @spamdoptions;
    push @spamdoptions, '--pidfile=/var/run/spamd.pid'
      if !grep { m/^--pidfile/ } @spamdoptions;

    return \@spamdoptions;
}

sub _check_cpanel_spamassassin_dir {
    my $self = shift;
    if ( !-e '/usr/local/cpanel/.spamassassin' ) {
        mkdir( '/usr/local/cpanel/.spamassassin', 0700 ) || do {
            $self->logger()->warn("The system failed to create the /usr/local/cpanel/.spamassassin file.");
        };
    }
    my @cpanel_pw = Cpanel::PwCache::getpwnam('cpanel');
    if ( $cpanel_pw[0] ) {
        chown $cpanel_pw[2], $cpanel_pw[3], '/usr/local/cpanel/.spamassassin';
    }
    return;
}

# used for test
sub _connect_to_spamc_binary {
    my $read_fh  = IO::Handle->new();
    my $write_fh = IO::Handle->new();

    my $pid = Cpanel::FastSpawn::InOut::inout( $write_fh, $read_fh, @_ );
    return $pid, $read_fh, $write_fh;
}

sub _spamdcheck {
    my $self = shift;

    my $raw_out;
    my $opt = $self->_getspamdopts();

    local $SIG{'ALRM'} = sub { die 'timeout' };

    $self->_check_cpanel_spamassassin_dir();

    my $spamc_binary = Cpanel::Binaries::path('spamc');
    if ( !-x $spamc_binary ) { return; }

    my $spamdstat = 0;
    eval {
        my ( $pid, $rdrfh, $wtrfh );

        # If we don't get a response in 150 seconds, something is very wrong
        alarm(150);
        require Cpanel::ArrayFunc;
        my ($socket_arg) = Cpanel::ArrayFunc::first( sub { defined $_ && index( $_, '--socketpath=' ) == 0 }, @{$opt} );
        if ($socket_arg) {
            my ( undef, $socket_path ) = split q{=}, $socket_arg;
            ( $pid, $rdrfh, $wtrfh ) = _connect_to_spamc_binary( $spamc_binary, '-K', '-u', 'cpanel', '-U', $socket_path );
        }
        else {
            ( $pid, $rdrfh, $wtrfh ) = _connect_to_spamc_binary( $spamc_binary, '-K', '-u', 'cpanel' );
        }

        # Close the write file handle
        close($wtrfh);

        # Process command output
        while (<$rdrfh>) {
            $raw_out .= $_;
            if (m{SPAMD/[0-9]+}) {
                $spamdstat = 1;
            }
        }

        # Close the read file handle
        close($rdrfh);

        waitpid( $pid, 0 );

        if ($?) {

            # check_with_message() expects undef return value when spamd is down.
            if ( ( $? >> 8 ) == Cpanel::SpamAssassin::Constants::EX_UNAVAILABLE() ) {
                $spamdstat = undef;
            }
            else {
                my $autopsy = Cpanel::ChildErrorStringifier->new($?)->autopsy();
                $raw_out .= $autopsy;
            }
        }

        alarm(0);
    };

    if ($@) {
        unless ( $@ =~ /timeout/ ) {
            alarm(0);
            die;
        }
    }

    # if not defined and no problems, then we can assume everything is working #
    #$spamdstat = 0 if !defined $spamdstat;

    return ( $spamdstat, $raw_out ) if wantarray;
    return $spamdstat;
}

sub start {
    my $self = shift;

    # this is for stuff like chksrvd and other process that parse service output... this probably need severe revisting due #
    # to messing with the system language settings #
    local $ENV{'LC_ALL'} = $ENV{'LANG'} = 'C';

    return $self->SUPER::start(@_);
}

sub check {
    my ($self) = @_;
    return ( $self->check_with_message() )[0];
}

sub check_with_message {
    my ($self) = @_;

    $self->check_sanity();

    # CPANEL-9894: Ensure that spamd will not be reported as down when exim is disabled.
    if ( !Cpanel::Services::Enabled::is_enabled('exim') ) {
        return ( 1, 'Exim is not enabled, check bypassed' );
    }

    my ( $spamdstat, $raw_out ) = $self->_spamdcheck();
    my %exception_parameters = ( 'service' => $self->service(), 'longmess' => undef, host => '127.0.0.1', port => $self->ports->[0], message => $raw_out );
    if ( !defined $spamdstat ) {
        die Cpanel::Exception::create( 'Service::IsDown', \%exception_parameters );
    }
    elsif ( !$spamdstat ) {
        $raw_out = '' if !defined $raw_out;
        print STDERR "Raw Output: $raw_out\n";
        die Cpanel::Exception::create( 'Services::BadResponse', [ %exception_parameters, 'error' => 'The service did not pass the built-in GTUBE test.' ] );
    }
    return ( 1, $raw_out . "\n" );
}

1;
