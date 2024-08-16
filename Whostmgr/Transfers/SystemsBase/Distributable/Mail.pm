package Whostmgr::Transfers::SystemsBase::Distributable::Mail;

# cpanel - Whostmgr/Transfers/SystemsBase/Distributable/Mail.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::SystemsBase::Distributable::Mail

=head1 DESCRIPTION

A L<Whostmgr::Transfers::SystemsBase::Distributable> subclass for restore
modules that pertain to C<Mail> distributable functionality.

=cut

#----------------------------------------------------------------------

use parent 'Whostmgr::Transfers::SystemsBase::Distributable';

use constant {
    _WORKER_TYPE => 'Mail',
};

1;
