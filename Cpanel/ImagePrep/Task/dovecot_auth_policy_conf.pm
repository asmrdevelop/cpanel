
# cpanel - Cpanel/ImagePrep/Task/dovecot_auth_policy_conf.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::dovecot_auth_policy_conf;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::FileUtils::Modify ();
use Cpanel::Rand::Get         ();
use Cpanel::Slurper           ();
use File::Path                ();    ##no critic(PreferredModules)

use Try::Tiny;

=head1 NAME

Cpanel::ImagePrep::Task::dovecot_auth_policy_conf - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
Pre- / post-snapshot actions for dovecot. Clears and regenerates the
dovecot auth policy hash nonce and key in /etc/dovecot/auth_policy.conf.
EOF
}

use constant CONF => '/etc/dovecot/auth_policy.conf';

sub _type { return 'non-repair only' }

sub _pre {
    my ($self) = @_;

    $self->{keys_backup} = $self->common->_rename_to_backup('/var/cpanel/cphulkd/keys');

    my $updated = Cpanel::FileUtils::Modify::match_replace(
        CONF(),
        [
            {
                match   => qr/^auth_policy_hash_nonce.*/m,
                replace => 'auth_policy_hash_nonce = REPLACE'
            },
            {
                match   => qr/^auth_policy_server_api_header.*/m,
                replace => 'auth_policy_server_api_header = X-API-Key:dovecot:REPLACE'
            },
        ]
    );

    if ( !$updated ) {
        $self->loginfo('There is no Dovecot auth policy key in the conf file');
        return $self->PRE_POST_NOT_APPLICABLE;    # but restart services anyway (see above) because cphulk changes were already made
    }

    $self->loginfo('Cleared Dovecot auth policy key');
    return $self->PRE_POST_OK;
}

sub _post {
    my ($self) = @_;

    # From Cpanel::AdvConfig::dovecot::_auth_policy_hash_nonce
    my $new_nonce = Cpanel::Rand::Get::getranddata( 8, [ 0 .. 9 ] );

    my $new_key;
    try {
        $self->common->run_command_full(
            program => '/usr/local/cpanel/bin/hulkdsetup',
            args    => [],
        );

        $new_key = Cpanel::Slurper::read('/var/cpanel/cphulkd/keys/dovecot');
    }
    catch {
        die "Failure during cphulk key regeneration: $_\n";
    };

    if ( !$new_key ) {
        if ( $self->{keys_backup} ) {    # Only possible or appropriate if pre and post are done in the same process
            $self->common->_rename( $self->{keys_backup}, '/var/cpanel/cphulkd/keys' );
        }
        die 'New key was either not generated or not readable';
    }
    if ( $self->{keys_backup} ) {
        $self->loginfo("Deleting $self->{keys_backup}");
        File::Path::rmtree( $self->{keys_backup} );
    }

    my %service_name_mapping = (    # cphulkd service name to restartsrvd script service name; see bin/hulkdsetup
        'dovecot'   => 'imap',
        'exim'      => 'exim',
        'pure-ftpd' => 'ftpd',
        'cpaneld'   => 'cpsrvd',
        'webmaild'  => 'cpsrvd',
        'whostmgrd' => 'cpsrvd',
        'cpdavd'    => 'cpdavd',
    );
    for my $cphulkd_service_name ( sort keys %service_name_mapping ) {
        my $restartsrv_service_name = $service_name_mapping{$cphulkd_service_name};
        if ( $restartsrv_service_name && -e "/var/cpanel/cphulkd/keys/$cphulkd_service_name" ) {
            $self->need_restart($restartsrv_service_name);
        }
    }

    my $updated = Cpanel::FileUtils::Modify::match_replace(
        CONF(),
        [
            {
                match   => qr/^auth_policy_hash_nonce.*/m,
                replace => "auth_policy_hash_nonce = $new_nonce"
            },
            {
                match   => qr/^auth_policy_server_api_header.*/m,
                replace => "auth_policy_server_api_header = X-API-Key:dovecot:$new_key"
            },
        ]
    );
    if ( !$updated ) {
        $self->loginfo('There is no Dovecot auth policy key in the conf file');
        return $self->PRE_POST_NOT_APPLICABLE;    # but restart services anyway (see above) because cphulk changes were already made
    }

    $self->loginfo('Regenerated Dovecot auth policy key');
    return $self->PRE_POST_OK;
}

1;
