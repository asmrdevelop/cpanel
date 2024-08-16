package Cpanel::Pkgacct::Components::DigestShadow;

# cpanel - Cpanel/Pkgacct/Components/DigestShadow.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::DigestShadow

=head1 SYNOPSIS

    my $obj = Cpanel::Pkgacct->new( ... );
    $obj->perform_component('DigestShadow');

=head1 DESCRIPTION

This module exists to be called from L<Cpanel::Pkgacct>. It should not be
invoked directly except from that module.

It backs up the user’s custom digest shadow to the account archive.

=head1 METHODS

=cut

use Try::Tiny;

use parent qw( Cpanel::Pkgacct::Component );

use Cpanel::FileUtils::Write ();

=head2 I<OBJ>->perform()

This is just here to satisfy cplint. Don’t call this directly.

=cut

sub perform {
    my ($self) = @_;

    my $digestpass;

    my $username = $self->get_user();
    if ($>) {
        require Cpanel::AdminBin;

        #READDIGEST fails if there’s no digest for the user,
        #so we first have to check if the digest exists.
        #Internally this means we’re opening/reading the file
        #twice when there’s an entry to back up.
        #It’s inefficient, alas.
        my $has_digest = Cpanel::AdminBin::adminrun( 'security', 'HASDIGEST', $username );
        if ($has_digest) {
            $digestpass = Cpanel::AdminBin::adminrun( 'security', 'READDIGEST', $username );
        }
    }
    else {
        require Cpanel::Auth::Digest::DB::Manage;

        #The normal get_entry() function doesn’t fail if there’s
        #no entry, so we’re good here.
        $digestpass = Cpanel::Auth::Digest::DB::Manage::get_entry($username);
    }

    my $work_dir = $self->get_work_dir();

    try {
        Cpanel::FileUtils::Write::overwrite(
            "$work_dir/digestshadow",
            $digestpass // q<>,
            0600,
        );
    }
    catch {
        local $@ = $_;
        warn;
    };

    return;
}

1;
