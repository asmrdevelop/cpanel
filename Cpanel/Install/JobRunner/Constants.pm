package Cpanel::Install::JobRunner::Constants;

# cpanel - Cpanel/Install/JobRunner/Constants.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Install::JobRunner::Constants

=head1 DESCRIPTION

Constants for cPanel & WHM installation jobs.

=cut

#----------------------------------------------------------------------

=head1 CONSTANTS

=head2 JOBS_NAMESPACE

The Perl namespace (i.e., a string) under which all install jobs must exist.

=cut

use constant {
    JOBS_NAMESPACE => 'Cpanel::Install::Job',
};

1;
