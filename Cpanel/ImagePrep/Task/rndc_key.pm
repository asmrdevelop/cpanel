
# cpanel - Cpanel/ImagePrep/Task/rndc_key.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::rndc_key;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';

use Cpanel::NameServer::Utils::BIND    ();
use Cpanel::NameServer::Utils::Enabled ();

=head1 NAME

Cpanel::ImagePrep::Task::rndc_key - An implementation subclass of
Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
Pre- / post-snapshot actions for rndc (a component of BIND). The rndc
key is only needed on systems using BIND, which is no longer the default,
but this task removes any key material regardless of the enabled name
server. If BIND is not enabled the post-snapshot task will be skipped.
EOF
}

sub _type { return 'non-repair only' }

sub _pre {
    my ($self) = @_;

    # All of the paths that Cpanel::DNSLib::find_rndckey uses
    my @paths = qw(
      /etc/rndc.key
      /etc/bind/rndc.key
      /etc/namedb/rndc.key
      /usr/local/etc/rndc.key
    );

    if ( my $chroot = Cpanel::NameServer::Utils::BIND::find_chrootbinddir() ) {
        push @paths, "$chroot/etc/rndc.key";
    }

    my $ok = 1;
    for my $f (@paths) {
        $ok = 0 if !$self->common->_unlink($f);
    }

    return $ok ? $self->PRE_POST_OK : $self->PRE_POST_FAILED;
}

sub _post {
    my ($self) = @_;

    if ( Cpanel::NameServer::Utils::Enabled::current_nameserver_is('bind') ) {
        $self->common->run_command( '/usr/local/cpanel/scripts/fixrndc', '--force', '--verbose' );
        $self->loginfo('Regenerated rndc.key');
        $self->need_restart('named');
        return $self->PRE_POST_OK;
    }

    return $self->PRE_POST_NOT_APPLICABLE;
}

1;
