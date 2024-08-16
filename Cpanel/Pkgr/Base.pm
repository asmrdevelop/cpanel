package Cpanel::Pkgr::Base;

# cpanel - Cpanel/Pkgr/Base.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Pkgr::Base

=head1 DESCRIPTION

This is a base class currently used by Cpanel::Pkgr::*

=head1 SYNOPSIS

=cut

use cPstrict;

sub new ( $class, $opts = undef ) {
    $opts //= {};

    my $self = {%$opts};
    bless $self, $class;

    return $self;
}

sub name ($self) { die "name unimplemented" }

sub get_package_version ( $self, $pkg ) {
    my $results = $self->get_version_for_packages($pkg) // {};

    return $results->{$pkg};
}

sub what_package_owns_this_file ( $self, $file ) {
    my $pkg_v = $self->what_owns($file) // {};

    my ($owner) = keys $pkg_v->%*;

    return $owner;
}

1;
