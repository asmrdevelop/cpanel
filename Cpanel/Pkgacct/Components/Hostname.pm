package Cpanel::Pkgacct::Components::Hostname;

# cpanel - Cpanel/Pkgacct/Components/Hostname.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::Hostname

=head1 SYNOPSIS

    my $obj = Cpanel::Pkgacct->new( ... );
    $obj->perform_component('Hostname');

=head1 DESCRIPTION

This module exists to be called from L<Cpanel::Pkgacct>. It should not be
invoked directly except from that module.

It backs up the server’s hostname so that migrations to the new hostname
can happen.

=head1 METHODS

=cut

use strict;
use warnings;

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::FileUtils::Write ();
use Cpanel::Sys::Hostname    ();

use constant RELATIVE_PATH => 'hostname';

=head2 I<OBJ>->perform()

This is just here to satisfy cplint. Don’t call this directly.

=cut

sub perform {
    my ($self) = @_;

    #save the new way
    Cpanel::FileUtils::Write::overwrite(
        $self->get_work_dir() . '/' . RELATIVE_PATH(),
        Cpanel::Sys::Hostname::gethostname(),
    );

    return 1;
}

1;
