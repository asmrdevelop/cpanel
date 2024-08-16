package Cpanel::ServiceManager::Services::Mailman;

# cpanel - Cpanel/ServiceManager/Services/Mailman.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::ServiceManager::Base ();
extends 'Cpanel::ServiceManager::Base';

use Cpanel::ConfigFiles     ();
use Cpanel::Mailman         ();
use Cpanel::SafeRun::Object ();

has '_have_lists' => ( is => 'ro', lazy => 1, default => sub { Cpanel::Mailman::have_lists() ? 1 : 0 } );

has '+is_cpanel_service' => ( is => 'ro', default => 1 );
has '+restart_attempts'  => ( is => 'ro', default => 2 );

has '+pidfile'               => ( is => 'ro', lazy => 1, default => sub { "$Cpanel::ConfigFiles::MAILMAN_ROOT/data/master-qrunner.pid" } );
has '+pid_exe'               => ( is => 'ro', lazy => 1, default => sub { qr/\/python(\d+(\.\d+)?)?$/ } );
has '+doomed_rules'          => ( is => 'ro', lazy => 1, default => sub { [qw{ mailman qrunner }] } );
has '+service_binary'        => ( is => 'ro', lazy => 1, default => sub { "$Cpanel::ConfigFiles::MAILMAN_ROOT/bin/mailmanctl" } );
has '+startup_args'          => ( is => 'ro', lazy => 1, default => sub { [qw{ -s start }] } );
has '+is_enabled'            => ( is => 'ro', lazy => 1, default => sub { Cpanel::Mailman::skipmailman() ? 0 : 1 } );
has '+is_configured'         => ( is => 'ro', lazy => 1, default => sub { $_[0]->_have_lists } );
has '+not_configured_reason' => ( is => 'rw', lazy => 1, default => sub { $_[0]->_have_lists ? undef : 'there are no configured mailing lists'; } );

use constant CLEAN_DEAD_MAILMAN_LOCKS_SCRIPT => '/usr/local/cpanel/scripts/clean_dead_mailman_locks';

sub start {
    my $self = shift;
    Cpanel::Mailman::setup_jail_flags();

    my $run = Cpanel::SafeRun::Object->new( 'program' => CLEAN_DEAD_MAILMAN_LOCKS_SCRIPT );

    if ( $run->CHILD_ERROR() ) {
        warn "Failed to call “" . CLEAN_DEAD_MAILMAN_LOCKS_SCRIPT . "” to list processes because of an error: " . $run->stderr() . " " . $run->autopsy();

    }

    return $self->SUPER::start(@_);
}

1;
