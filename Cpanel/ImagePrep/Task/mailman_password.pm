
# cpanel - Cpanel/ImagePrep/Task/mailman_password.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::mailman_password;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::Imports;
use Cpanel::Pkgr ();

=head1 NAME

Cpanel::ImagePrep::Task::mailman_password - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
Pre- / post-snapshot actions for mailman. Clears and regenerates mailman password(s).
EOF
}

use constant MAILMAN => '/usr/local/cpanel/3rdparty/mailman';

sub _type { return 'non-repair only' }

sub _pre {
    my ($self) = @_;

    $self->common->_unlink('/var/cpanel/mmpass');
    $self->common->_rename_to_backup( MAILMAN() );

    my $ok = ( !$self->common->_exists('/var/cpanel/mmpass') && !$self->common->_exists( MAILMAN() ) );
    if ( !$ok ) {
        $self->loginfo('Failed to clear mailman password');
        return $self->PRE_POST_FAILED;
    }

    for (qw(cpanel-mailman)) {
        $self->loginfo("Deleting any existing package named '$_' ...");
        Cpanel::Pkgr::remove_packages_nodeps($_);
    }

    $self->loginfo('Cleared Mailman password and uninstalled Mailman');

    return $self->PRE_POST_OK;
}

sub _post {
    my ($self) = @_;

    my $ok;
    for my $try ( 1 .. 7 ) {
        $self->common->run_command_full(
            program => '/usr/local/cpanel/scripts/check_cpanel_pkgs',
            args    => [ '--fix', '--targets', 'mailman' ],
        );

        # Jan 2023: The check_cpanel_pkgs exit status can't be trusted to determine
        # whether the installation succeeded or not. Certain types of errors related
        # to dpkg locks are not converted into nonzero exits.
        $ok = $self->common->_exists('/var/cpanel/mmpass');
        last if $ok;

        $self->loginfo("mailman_password try $try of 7 failed");
        unless ( $try == 7 ) {
            my $sleep_time = 2**$try;
            $self->loginfo("Sleeping for $sleep_time seconds before trying again ...");
            $self->common->_sleep($sleep_time);
        }
    }

    if ( !$ok ) {
        $self->loginfo('Failed to regenerate mailman password');
        return $self->PRE_POST_FAILED;
    }

    $self->common->run_command_full(
        program => '/usr/local/cpanel/scripts/set_mailman_archive_perms',
    );
    $self->loginfo('Reinstalled Mailman / Regenerated Mailman password');
    return $self->PRE_POST_OK;
}

1;
