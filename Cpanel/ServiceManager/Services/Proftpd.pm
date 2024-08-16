package Cpanel::ServiceManager::Services::Proftpd;

# cpanel - Cpanel/ServiceManager/Services/Proftpd.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Moo;
extends 'Cpanel::ServiceManager::Base';

use cPstrict;    # restore hints

use Cpanel::FindBin           ();
use Cpanel::FtpUtils::Config  ();
use Cpanel::ConfigFiles       ();
use Cpanel::RestartSrv        ();
use Cpanel::SafetyBits        ();
use Cpanel::Services::Enabled ();

has '_use_proftpd' => ( is => 'ro', lazy => 1, builder => 1 );

has '+service_binary' => ( is => 'rw', lazy    => 1, default => sub { Cpanel::FindBin::findbin('proftpd') } );
has '+processowner'   => ( is => 'ro', default => 'proftpd' );
has '+is_configured'  => ( is => 'rw', lazy    => 1, default => sub ($self) { $self->_use_proftpd } );
has '+is_enabled'     => ( is => 'rw', lazy    => 1, default => sub ($self) { $self->_use_proftpd } );
has '+ports' => (
    lazy    => 1,
    is      => 'ro',
    default => sub {
        return [ eval { Cpanel::FtpUtils::Config->new()->get_port() } || 21 ];
    }
);
has '+service_package'  => ( is => 'ro', default => 'proftpd' );
has '+pidfile'          => ( is => 'ro', default => '/var/proftpd.pid' );
has '+restart_attempts' => ( is => 'ro', default => 3 );

sub _build__use_proftpd ($self) {
    return 0 unless ( ( $self->cpconf->{'ftpserver'} // '' ) eq 'proftpd' );
    return Cpanel::Services::Enabled::is_enabled('ftp') == 1 ? 1 : 0;
}

sub restart_attempt ( $self, $attempt = 1 ) {

    my $file = $Cpanel::ConfigFiles::FTP_PASSWD_DIR . q{/passwd.vhosts};
    if ( ( $attempt == 1 && !-f $file ) || $attempt == 2 ) {
        return 0 unless system('/usr/local/cpanel/bin/ftpupdate') == 0;
    }

    # here as a protection to fix permissions on the passwd.vhosts file
    if ( -f $file ) {
        Cpanel::SafetyBits::safe_chmod( 0640, 'root', $file );
        Cpanel::SafetyBits::safe_chown( 'root', 'proftpd', $file );
    }

    if ( $attempt >= 2 ) {

        # On the third restart attempt, do a last ditch effort
        # by rebuilding the config.

        my $msg = sprintf( 'The system failed %d times to restart %s. The system will now rebuild the service configuration.', $attempt, $self->service() );
        $self->logger()->info($msg);

        Cpanel::RestartSrv::logged_startup( $self->service(), 1, [ '/usr/local/cpanel/bin/build_ftp_conf', '--no-restart' ], 'wait' => 1 );

        return 0 if $?;
    }

    return 1;
}

1;
