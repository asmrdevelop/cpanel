package Whostmgr::Resellers::Check;

# cpanel - Whostmgr/Resellers/Check.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Whostmgr::Resellers::Check

=head1 SYNOPSIS

    #die()s on failure to discern whether $username is a reseller
    my $is_reseller = Whostmgr::Resellers::Check::is_reseller($username);

=cut

use strict;
use warnings;

use Cpanel::ConfigFiles ();
use Cpanel::LoadFile    ();

#overridden in tests
our $_RESELLERS_FILE;
*_RESELLERS_FILE = \$Cpanel::ConfigFiles::RESELLERS_FILE;

sub is_reseller {
    my $user = shift || die 'Need a username!';

    my $resellers_txt = Cpanel::LoadFile::load($_RESELLERS_FILE);

    return ( $resellers_txt =~ m<^\Q$user\E:>m ) ? 1 : 0;
}

1;
