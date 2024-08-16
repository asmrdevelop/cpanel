
# cpanel - Cpanel/ImagePrep/Task/mainip.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::mainip;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';
use Cpanel::Imports;
use Cpanel::Autodie ();

=head1 NAME

Cpanel::ImagePrep::Task::mainip - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
Clear the mainip file and run mainipcheck.
EOF
}

sub _type { return 'non-repair only' }

sub _pre {
    my ($self) = @_;
    return $self->common->_unlink('/var/cpanel/mainip') ? $self->PRE_POST_OK : $self->PRE_POST_FAILED;
}

sub _post {
    my ($self) = @_;

    $self->common->run_command('/usr/local/cpanel/scripts/mainipcheck');

    return $self->PRE_POST_OK;
}

sub _deps {
    return;
}

1;
