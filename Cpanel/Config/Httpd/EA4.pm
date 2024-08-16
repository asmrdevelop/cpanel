package Cpanel::Config::Httpd::EA4;

# cpanel - Cpanel/Config/Httpd/EA4.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Config::Httpd::EA4

=head1 SYNOPSIS

    if ( Cpanel::Config::Httpd::EA4::is_ea4() ) { ... }

=head1 DESCRIPTION

Nothing outlandish here: This module is just a lightweight way to see
if the current system identifies as running EasyApache 4.

=head1 METHODS

=cut

use strict;
use warnings;

use Cpanel::Autodie ();

#overridden in tests
our $_FLAG_FILE = '/etc/cpanel/ea4/is_ea4';

=head2 $yn = is_ea4()

Returns 1 or 0 to indicate whether the system identifies as running EA4.
Throws an exception if a filesystem error (e.g., EACCES) prevents us from
retrieving this information.

=cut

my $is_ea4_cached;

sub is_ea4 {
    return $is_ea4_cached //= _is_ea4();
}

#----------------------------------------------------------------------

sub _is_ea4 {
    return Cpanel::Autodie::exists($_FLAG_FILE) ? 1 : 0;
}

#This should probably only be called from tests
#or when migrating a system from EA3 to EA4.
sub reset_cache {
    undef $is_ea4_cached;
    return;
}

1;
