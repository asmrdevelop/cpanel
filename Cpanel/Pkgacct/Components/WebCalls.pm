package Cpanel::Pkgacct::Components::WebCalls;

# cpanel - Cpanel/Pkgacct/Components/WebCalls.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::WebCalls

=head1 SYNOPSIS

    my $obj = Cpanel::Pkgacct->new( ... );
    $obj->perform_component('WebCalls');

=head1 DESCRIPTION

This module exists to be called from L<Cpanel::Pkgacct>. It should not be
invoked directly except from that module.

It backs up the user’s web calls information.

=head1 METHODS

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::FileUtils::Write ();
use Cpanel::JSON             ();

use constant RELATIVE_PATH => 'webcalls.json';

#----------------------------------------------------------------------

=head2 I<OBJ>->perform()

This is just here to satisfy cplint. Don’t call this directly.

=cut

sub perform {
    my ($self) = @_;

    my $entries_hr;

    if ($>) {
        require Cpanel::AdminBin::Call;
        $entries_hr = Cpanel::AdminBin::Call::call(
            'Cpanel', 'webcalls', 'GET_ENTRIES',
        );
    }
    else {
        require Cpanel::WebCalls::Datastore::Read;
        $entries_hr = Cpanel::WebCalls::Datastore::Read->read_for_user(
            $self->get_user(),
        );
    }

    if (%$entries_hr) {
        Cpanel::FileUtils::Write::overwrite(
            $self->get_work_dir() . '/' . RELATIVE_PATH(),
            Cpanel::JSON::Dump($entries_hr),
        );
    }

    return 1;
}

1;
