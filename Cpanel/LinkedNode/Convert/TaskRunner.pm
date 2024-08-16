package Cpanel::LinkedNode::Convert::TaskRunner;

# cpanel - Cpanel/LinkedNode/Convert/TaskRunner.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::TaskRunner

=head1 DESCRIPTION

This module implements
L<Cpanel::LinkedNode::Convert::ToDistributed> and
L<Cpanel::LinkedNode::Convert::FromDistributed>’s
task-runner logic.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::TaskRunner';

use Cpanel::Imports;

#----------------------------------------------------------------------

sub _FAILURE_MESSAGE {
    return locale()->maketext('The account conversion process failed.');
}

1;
