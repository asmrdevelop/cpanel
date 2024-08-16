package Cpanel::AdvConfig::Setup;

# cpanel - Cpanel/AdvConfig/Setup.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::SafeDir::MK                  ();

our $system_store_dir = '/var/cpanel/conf';

=encoding utf-8

=head1 NAME

Cpanel::AdvConfig::Setup - Tools to setup AdvConfig for a service

=head1 SYNOPSIS

    use Cpanel::AdvConfig::Setup ();

    Cpanel::AdvConfig::Setup::ensure_conf_dir_exists('dovecot');

=head2 ensure_conf_dir_exists($service)

Creates the AdvConfig configuration directory for a given
$service if it does not already exist.

=cut

sub ensure_conf_dir_exists {
    my ($service) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($service);
    Cpanel::SafeDir::MK::safemkdir( "$system_store_dir/$service", '0700' );

    return;
}

1;
