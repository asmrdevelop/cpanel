package Cpanel::EA4::Constants;

# cpanel - Cpanel/EA4/Constants.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Test::Cpanel::Policy - constants

use strict;
use warnings;
use Cpanel::OS ();

# please do not bring other dependencies there, it should stay light

use constant nginx_pkg             => "ea-nginx";
use constant nginx_domain_logs_dir => "/var/log/nginx/domains";

# URL to public signing key for RPM signing verification
our $public_key_url = 'https://securedownloads.cpanel.net/cPanelPublicPkgKey.asc';

our $ea4_dir       = '/etc/cpanel/ea4';
our $ea4_dir_perms = 0755;
our $ea4_flag_file = $ea4_dir . '/is_ea4';

our $public_key_path = '/etc/cpanel/ea4/cPanelPublicPkgKey.asc';

sub repo_file_url {
    return Cpanel::OS::ea4_from_bare_repo_url();
}

sub repo_file_path {
    return Cpanel::OS::ea4_from_bare_repo_path();
}

1;

=pod

=head1 NAME

Cpanel::EA4::Constants

=head1 DESCRIPTION

This package provides shared configuration variables and should not bring
any extra dependencies.

=head1 FUNCTIONS

none

=cut
