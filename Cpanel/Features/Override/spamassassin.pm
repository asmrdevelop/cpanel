package Cpanel::Features::Override::spamassassin;

# cpanel - Cpanel/Features/Override/spamassassin.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Features::Override::spamassassin

=head1 SYNOPSIS

See the base class.

=head1 DESCRIPTION

This module extends L<Cpanel::Features::Override> for the
C<spamassassin> feature.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Features::Override';

#----------------------------------------------------------------------

sub _LOCAL_ROLE {
    return 'SpamFilter';
}

sub _CHILD_WORKLOAD {
    return 'Mail';
}

1;
