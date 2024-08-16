package Cpanel::Config::Httpd::Paths;

# cpanel - Cpanel/Config/Httpd/Paths.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Config::Httpd::Paths - Get path of various Apache assets

=head1 SYNOPSIS

    use Cpanel::Config::Httpd::Paths ();

    my $httpd_base_dir = Cpanel::Config::Httpd::Paths::default_httpd_dir();
    my $suexec_binary_location = Cpanel::Config::Httpd::Paths::suexec_binary_location();
    my $splitlogs_binary_location = Cpanel::Config::Httpd::Paths::splitlogs_binary_location();

=cut

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics

our $CPANEL_ROOT      = '/usr/local/cpanel';
our $PRODUCT_CONF_DIR = '/var/cpanel';
our $SYSTEM_RUN_DIR   = '/var/run';

# Data mocking routines (i.e. to make them feel bad)
sub default_cpanel_dir {
    $CPANEL_ROOT = shift if @_;
    return $CPANEL_ROOT;
}

sub default_product_dir {
    $PRODUCT_CONF_DIR = shift if @_;
    return $PRODUCT_CONF_DIR;
}

sub default_run_dir {
    $SYSTEM_RUN_DIR = shift if @_;
    return $SYSTEM_RUN_DIR;
}

=head2 default_httpd_dir( DIR )

If a defined value is given for DIR, returns that value. Otherwise, this
returns C<httpd>’s base directory.

=cut

sub default_httpd_dir {
    my $HTTPD_BASE_DIR = shift;

    # Parentheses are required for apache_paths_facade here.
    return ( defined $HTTPD_BASE_DIR ) ? $HTTPD_BASE_DIR : apache_paths_facade()->dir_base();
}

=head2 suexec_binary_location()

Returns the path to the suexec binary.

=cut

sub suexec_binary_location {
    my $dir = default_httpd_dir();
    return $dir eq apache_paths_facade->dir_base() ? apache_paths_facade->bin_suexec() : default_httpd_dir() . '/bin/suexec';
}

=head2 splitlogs_binary_location()

Returns the path to the splitlogs binary.

=cut

sub splitlogs_binary_location {
    return default_cpanel_dir() . '/bin/splitlogs';
}

1;
