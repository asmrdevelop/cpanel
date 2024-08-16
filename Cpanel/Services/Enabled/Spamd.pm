package Cpanel::Services::Enabled::Spamd;

# cpanel - Cpanel/Services/Enabled/Spamd.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Services::Enabled::Spamd

=head1 SYNOPSIS

    $yn = Cpanel::Services::Enabled::Spamd::is_enabled()

=head1 DESCRIPTION

This module exists for contexts like Exim’s Perl where we need
to be as light as possible about determining whether spamd (i.e.,
SpamAssassin) is enabled.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie::More::Lite ();

# accessed from tests
our $_TOUCHFILE_PATH = '/etc/spamddisable';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = is_enabled()

Returns a boolean that indicates whether spamd is enabled—which
is to say: whether spamd is I<not> marked disabled.

If an error happens during the check, an exception is thrown.

=cut

sub is_enabled {
    return !Cpanel::Autodie::More::Lite::exists($_TOUCHFILE_PATH);
}

1;
