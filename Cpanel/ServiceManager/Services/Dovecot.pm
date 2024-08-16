package Cpanel::ServiceManager::Services::Dovecot;

# cpanel - Cpanel/ServiceManager/Services/Dovecot.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Moo;
extends 'Cpanel::ServiceManager::Base';

use Cpanel::RestartSrv ();
use Cpanel::Kill       ();

has '+service_package' => ( is => 'ro', lazy => 1, default => sub { ['dovecot'] } );
has '+doomed_rules'    => ( is => 'ro', lazy => 1, default => sub { [ 'authProg', 'authdaemond', 'imapd', 'pop3', 'imap-login', 'pop3-login', 'dovecot/lmtp', 'dovecot', 'dovecot-auth', 'dovecot-wrap' ] } );
has '+ports'           => ( is => 'ro', lazy => 1, default => sub { [qw{ 110 993 995 143 }] } );

has '+pidfile'          => ( is => 'ro', default => '/var/run/dovecot/master.pid' );
has '+restart_attempts' => ( is => 'ro', default => 4 );
has '+support_reload'   => ( is => 'ro', default => 1 );
has '+is_enabled'       => ( is => 'ro', default => 1 );
has '+is_configured'    => ( is => 'ro', default => 1 );
has '+service_binary'   => ( is => 'ro', default => q{/usr/sbin/dovecot} );

sub start {
    my ( $self, @args ) = @_;

    $self->debug("Killing all remaining dovecot-wrap processes");
    Cpanel::Kill::killall( 'HUP', 'dovecot-wrap' );

    return $self->SUPER::start(@args);
}

sub restart_attempt {
    my ( $self, $p_attempt ) = @_;

    if ( $p_attempt == 2 ) {
        $self->info("Domming remaining dovecot processes");
        eval { $self->service_manager->stop($self) };
    }
    elsif ( $p_attempt == 3 ) {
        $self->info( q{The service '} . $self->service() . q{' failed to restart at least three times. The system will now rebuild the SNI conf files.} );
        Cpanel::RestartSrv::logged_startup( $self->service(), 1, [ '/usr/local/cpanel/scripts/build_mail_sni', '--rebuild_map_file', '--rebuild_dovecot_sni_conf' ], 'wait' => 1 );
        return 1;
    }
    elsif ( $p_attempt == 4 ) {
        $self->info( q{The service '} . $self->service() . q{' failed to restart at least four times. The system will now rebuild the main conf files.} );
        Cpanel::RestartSrv::logged_startup( $self->service(), 1, ['/usr/local/cpanel/scripts/builddovecotconf'], 'wait' => 1 );
        return 1;
    }

    return 0;
}

1;
