
# cpanel - Cpanel/ImagePrep/Task/chkservd_credentials.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::chkservd_credentials;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::Imports;
use Cpanel::ServiceAuth ();

use Try::Tiny;

=head1 NAME

Cpanel::ImagePrep::Task::chkservd_credentials - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
Pre- / post-snapshot actions for chkservd credentials. Clears and
regenerates credentials under /var/cpanel/serviceauth.
EOF
}

sub _type { return 'non-repair only' }

sub _pre {
    my ($self) = @_;

    foreach my $service ( sort $self->_services() ) {
        $self->common->_unlink("/var/cpanel/serviceauth/${service}/send");
        $self->common->_unlink("/var/cpanel/serviceauth/${service}/recv");
    }

    $self->loginfo('Cleared chkservd credentials');
    return $self->PRE_POST_OK;
}

sub _post {
    my ($self) = @_;

    foreach my $service ( sort $self->_services() ) {
        try {
            $self->loginfo("Generating serviceauth keys for $service");
            Cpanel::ServiceAuth->new($service)->generate_authkeys_if_missing();

            $self->need_restart($service);
        }
        catch {
            die "Failure during serviceauth credential regeneration for ${service}: $_\n";
        };
    }
    $self->loginfo('Regenerated chkservd credentials');
    return $self->PRE_POST_OK;
}

sub _services {
    my $self = shift;
    return map { ( split '/' )[-1] } grep { -d } $self->common->_glob('/var/cpanel/serviceauth/*');
}

1;
