
# cpanel - Cpanel/ImagePrep/Task/license.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::license;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::Imports;

use Try::Tiny;

=head1 NAME

Cpanel::ImagePrep::Task::license - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
Clear cPanel & WHM license-related files before snapshotting. Activate
the license for a newly launched instance, if available.
EOF
}

sub _type { return 'non-repair only' }

sub _pre {
    my ($self) = @_;

    my $ok = 1;
    for my $f (
        qw(
        /usr/local/cpanel/cpanel.lisc
        /usr/local/cpanel/cpsanitycheck.so
        /var/cpanel/companyid
        /var/cpanel/companyid.fast
        /var/cpanel/licenseid_credentials.json
        /var/cpanel/license.status.json
        )
    ) {
        $ok = 0 if !$self->common->_unlink($f);
    }

    return $ok ? $self->PRE_POST_OK : $self->PRE_POST_FAILED;
}

sub _post {
    my ($self) = @_;
    try {
        $self->common->run_command('/usr/local/cpanel/cpkeyclt');
    }
    catch {
        # Can't consider this a failure because it will be normal for BYOL-type setups.
        $self->loginfo(q{It looks like we were not able to activate a cPanel & WHM license on this server. If you have not obtained a license for the server's IP address yet, then this is expected.});
    };
    return $self->PRE_POST_OK;
}

sub _deps {
    return qw(mainip);
}

1;
