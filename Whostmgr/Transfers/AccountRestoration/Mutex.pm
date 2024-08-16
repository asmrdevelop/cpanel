package Whostmgr::Transfers::AccountRestoration::Mutex;

# cpanel - Whostmgr/Transfers/AccountRestoration/Mutex.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::AccountRestoration::Mutex

=head1 SYNOPSIS

See the base class.

=head1 DESCRIPTION

This class implements L<Cpanel::UserMutex::Privileged>.
Its intended use is to indicate that an account restoration is in progress.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::UserMutex::Privileged';

#----------------------------------------------------------------------

1;
