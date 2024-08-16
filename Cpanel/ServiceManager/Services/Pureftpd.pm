package Cpanel::ServiceManager::Services::Pureftpd;

# cpanel - Cpanel/ServiceManager/Services/Pureftpd.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Moo;
extends 'Cpanel::ServiceManager::Base';

use cPstrict;    # restore hints

use Cpanel::Exception         ();
use Cpanel::FtpUtils::Config  ();
use Cpanel::RestartSrv        ();
use Cpanel::Services::Enabled ();

has '_use_pureftpd' => ( is => 'ro', lazy => 1, builder => 1 );

has '+is_configured' => ( is => 'rw', lazy => 1, default => sub ($self) { $self->_use_pureftpd } );
has '+is_enabled'    => ( is => 'rw', lazy => 1, default => sub ($self) { $self->_use_pureftpd } );
has '+startup_args'  => ( is => 'ro', lazy => 1, default => sub { [qw{/etc/pure-ftpd.conf -O clf:/var/log/xferlog}] } );
has '+doomed_rules'  => ( is => 'ro', lazy => 1, default => sub { [ 'pure-ftpd', 'pure-authd' ] } );
has '+ports' => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        [ eval { Cpanel::FtpUtils::Config->new()->get_port() } || 21 ]
    }
);

has '+service_override' => ( is => 'ro', default => 'pure-ftpd' );
has '+service_package'  => ( is => 'ro', default => 'pure-ftpd' );
has '+service_binary'   => ( is => 'ro', default => '/usr/sbin/pure-config.pl' );
has '+pidfile'          => ( is => 'ro', default => '/var/run/pure-ftpd.pid' );
has '+restart_attempts' => ( is => 'ro', default => 3 );

sub _build__use_pureftpd ($self) {

    return 0 unless ( $self->cpconf->{'ftpserver'} // '' ) eq 'pure-ftpd';
    return Cpanel::Services::Enabled::is_enabled('ftp') == 1 ? 1 : 0;
}

sub restart_attempt ( $self, $attempt = 1 ) {

    if ( $attempt == 2 ) {
        Cpanel::RestartSrv::logged_startup( $self->service(), 1, [ '/usr/local/cpanel/bin/build_ftp_conf', '--no-restart' ], 'wait' => 1 );
        return 0 if $?;
    }

    return 1;
}

sub check ( $self, @args ) {

    return 0 unless $self->SUPER::check(@args);

    my $out = Cpanel::RestartSrv::check_service(
        'service' => 'pure-authd', 'user' => $self->processowner(),
        'pidfile' => '/var/run/pure-authd.pid'
    );
    die Cpanel::Exception::create( 'Service::IsDown', [ 'service' => 'pure-authd' ] )
      if !$out;

    return 1;
}

1;
