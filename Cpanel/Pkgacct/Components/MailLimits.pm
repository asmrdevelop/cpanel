package Cpanel::Pkgacct::Components::MailLimits;

# cpanel - Cpanel/Pkgacct/Components/MailLimits.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::MailLimits

=head1 SYNOPSIS

    my $obj = Cpanel::Pkgacct->new( ... );
    $obj->perform_component('MailLimits');

=head1 DESCRIPTION

This module exists to be called from L<Cpanel::Pkgacct>. It should not be
invoked directly except from that module.

It backs up the user’s outgoing email holds and suspensions.

=head1 METHODS

=cut

use strict;
use warnings;

use Cpanel::Autodie                ();
use Cpanel::Email::Accounts::Paths ();
use Cpanel::FileUtils::Copy        ();

use parent 'Cpanel::Pkgacct::Component';

=head2 I<OBJ>->perform()

This is just here to satisfy cplint. Don’t call this directly.

=cut

sub perform {

    my ($self) = @_;

    my $user     = $self->get_user;
    my $work_dir = $self->get_work_dir;

    my $limits_path = "$Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_BASE_PATH/$user/$Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_FILE_NAME";

    if ( Cpanel::Autodie::exists($limits_path) ) {
        Cpanel::FileUtils::Copy::safecopy( $limits_path, "$work_dir/$Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_FILE_NAME" );
    }

    return 1;
}

1;
