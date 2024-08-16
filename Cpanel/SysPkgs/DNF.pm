package Cpanel::SysPkgs::DNF;

# cpanel - Cpanel/SysPkgs/DNF.pm                    Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::SysPkgs::YUM';

=head1 NAME

Cpanel::SysPkgs::DNF

=head1 SYNOPSIS

    # you want to use Cpanel::SysPkgs instead
    my $pkg = Cpanel::SysPkgs->new;

See Cpanel::SysPkgs

=head1 DESCRIPTION

Provides DNF logic in addition to the YUM one.

=head1 METHODS

=cut

use Cpanel::Binaries::Dnf ();

sub _dnf ($self) {
    return $self->{_dnf} //= Cpanel::Binaries::Dnf->new();
}

=head2 enable_module_stream ( $self, $module, $version )

Enable a DNF module; e.g. postgresql:9.6
Note: this enables a single stream.

=cut

sub enable_module_stream ( $self, $module, $version ) {

    die "enable_module_stream needs a module and a version" unless defined $module && defined $version;

    my $name = qq[${module}:${version}];

    $self->out("Enabling dnf module '$name'");
    my $run = $self->_dnf->cmd( qw(module enable -y), $name );

    if ( $run->{status} != 0 ) {
        die "Failed to enable module '$name': " . ( $run->{output} // '' );
    }

    return 1;
}

=head2 disable_module ( $self, $module )

Disable a DNF module. All related module streams will become unavailable.
Note: this disables all streams in a module as opposed to enable_module_stream which is one stream.

=cut

sub disable_module ( $self, $module ) {
    die "disable_module needs a module name" unless defined $module;

    $self->out("Disabling package module $module");

    my $run = $self->_dnf->cmd( qw(module disable -y --quiet), $module );

    return $run->{status} ? 0 : 1;
}

1;
