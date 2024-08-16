package Cpanel::PackMan::Sys::dnf;

# cpanel - Cpanel/PackMan/Sys/dnf.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;    # must be after Moo
use File::Glob ();

our $VERSION = "0.01";

extends 'Cpanel::PackMan::Sys::yum';    # fortunately, for now they are 1 to 1 compat w/ yum. Can extend when that is no longer the case

has '+syscmd_binary' => (
    is       => 'ro',
    init_arg => undef,
    default  => '/usr/bin/dnf',
);

has '+cmd_failure_hint' => (
    is       => 'ro',
    init_arg => undef,
    default  => 'dnf makecache',
);

has '+universal_hooks_post_pkg_pattern' => (
    is       => 'ro',
    init_arg => undef,
    default  => "/etc/dnf/universal-hooks/pkgs/%s/transaction/%s",
);

sub is_unavailable ($self) {

    return 1 if File::Glob::bsd_glob("/var/cache/dnf/*.pid");
    return 1 if File::Glob::bsd_glob("/var/lib/dnf/*.pid");

    return 0;
}

sub syscmd_args_txn ( $self, $file ) {
    $self->_yummify_txn_file($file);
    return ( qw(-y --verbose shell), $file );
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::PackMan::Sys::dnf - Implements dnf support for Cpanel::PackMan

=head1 VERSION

This document describes Cpanel::PackMan::Sys::dnf version 0.01

=head1 SYNOPSIS

Do not use directly. Instead use L<Cpanel::PackMan>.

=head1 DESCRIPTION

Subclass of L<Cpanel::PackMan::Sys> implementing C<dnf> support for PackMan.

Currently it is the same as C<yum> and only overrides C<syscmd_binary> and C<cmd_failure_hint>.

