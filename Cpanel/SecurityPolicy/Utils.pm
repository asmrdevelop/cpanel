package Cpanel::SecurityPolicy::Utils;

# cpanel - Cpanel/SecurityPolicy/Utils.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#use strict;
use Cpanel::UserFiles ();

# TODO : Need to add these directories to the include path.
my $cpanel_libdir = '/usr/local/cpanel';
my $user_libdir   = '/var/cpanel/perl5/lib';
my $secpol_ns     = 'Cpanel::Security::Policy';

sub cpanel_libdir      { return $cpanel_libdir; }
sub user_libdir        { return $user_libdir; }
sub security_policy_ns { return $secpol_ns; }

sub secpol_dir_from_homedir {
    my ($homedir) = @_;

    return Cpanel::UserFiles::homedir_security_policy_dir($homedir);
}

sub secpol_dir_from_user {
    my ($user) = @_;

    return Cpanel::UserFiles::user_security_policy_dir($user);
}

1;
