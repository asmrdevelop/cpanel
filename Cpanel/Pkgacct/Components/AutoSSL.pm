package Cpanel::Pkgacct::Components::AutoSSL;

# cpanel - Cpanel/Pkgacct/Components/AutoSSL.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::AutoSSL

=head1 SYNOPSIS

    my $obj = Cpanel::Pkgacct->new( ... );
    $obj->perform_component('AutoSSL');

=head1 DESCRIPTION

This module exists to be called from L<Cpanel::Pkgacct>. It should not be
invoked directly except from that module.

It backs up the user’s custom AutoSSL configuration parameters to the
account archive.

=head1 METHODS

=cut

use strict;
use warnings;

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::FileUtils::Write        ();
use Cpanel::JSON                    ();
use Cpanel::SSL::Auto::Exclude::Get ();

=head2 I<OBJ>->perform()

This is just here to satisfy cplint. Don’t call this directly.

=cut

sub perform {
    my ($self) = @_;

    my $work_dir = $self->get_work_dir();

    my @domains = Cpanel::SSL::Auto::Exclude::Get::get_user_excluded_domains( $self->get_user() );

    my $json = Cpanel::JSON::Dump(
        {
            excluded_domains => \@domains,
        }
    );

    #
    # case CPANEL-15538: We need to overwrite here since incremental
    # will backup to the same place
    #
    Cpanel::FileUtils::Write::overwrite( "$work_dir/autossl.json", $json );

    return 1;
}

1;
