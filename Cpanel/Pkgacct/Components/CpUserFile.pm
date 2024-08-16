package Cpanel::Pkgacct::Components::CpUserFile;

# cpanel - Cpanel/Pkgacct/Components/CpUserFile.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::CpUserFile

=head1 DESCRIPTION

A pkgacct component to back up a user’s cpuser file.
It subclasses L<Cpanel::Pkgacct::Component> and isn’t meant to be called
directly except by pkgacct.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::Config::CpUser        ();
use Cpanel::Config::CpUser::Write ();
use Cpanel::FileUtils::Write      ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<OBJ>->perform()

Does the module’s work.

=cut

sub perform ($self) {
    my $username = $self->get_user();

    my %cpuser = %{ $self->get_cpuser_data() };

    if ( $self->get_attr('OPTS')->{'skiplinkednodes'} ) {
        require Cpanel::LinkedNode::Worker::GetAll;
        require Cpanel::LinkedNode::Worker::Storage;

        for my $worker_type ( Cpanel::LinkedNode::Worker::GetAll::RECOGNIZED_WORKER_TYPES() ) {
            Cpanel::LinkedNode::Worker::Storage::unset(
                \%cpuser,
                $worker_type,
            );
        }
    }

    my $clean_data = Cpanel::Config::CpUser::clean_cpuser_hash( \%cpuser, $username );
    if ( !$clean_data ) {
        die "Failed to preprocess cpuser data for user “$username”.";
    }

    my $work_dir = $self->get_work_dir();

    Cpanel::FileUtils::Write::overwrite(
        "$work_dir/cp/$username",
        Cpanel::Config::CpUser::Write::serialize($clean_data),
    );

    return;
}

1;
