package Cpanel::Config::CpUser::Object::Update;

# cpanel - Cpanel/Config/CpUser/Object/Update.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Config::CpUser::Object::Update

=head1 SYNOPSIS

    Cpanel::Config::CpUser::Object::Update::set_contact_emails(
        $cpuser_obj,
        [ 'old@email.tld' ],
        [ 'new@email.tld', 'alt-new@email.tld' ],
    );

=head1 DESCRIPTION

This module implements functionality to update
L<Cpanel::Config::CpUser::Object> instances. It’s not kept inside
L<Cpanel::Config::CpUser::Object> itself because it’s rarely used,
and we want to keep that module as light as possible.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception          ();
use Cpanel::Validate::EmailRFC ();
use Cpanel::Set                ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 set_contact_emails( $CPUSER_OBJ, \@OLD_ADDRS, \@NEW_ADDRS )

Updates $CPUSER_OBJ’s stored contact email addresses.

@OLD_ARGS B<MUST> match $CPUSER_OBJ’s status quo. This is done to
encourage race-safe designs. You can, of course, just pass in
C<$CPUSER_OBJ-E<gt>contact_emails_ar()> to defeat it; that’s reasonable
in legacy code, but please don’t do that in new stuff.

Returns nothing. May throw the following:

=over

=item * L<Cpanel::Exception::Stale>, if the old addresses are incorrect.
(The C<addresses> parameter will be an arrayref of the expected old
addresses.)

=item * L<Cpanel::Exception::InvalidParameter>, if some other part of the
submission is wrong (which the caller should have caught before calling
this function).

=back

=cut

sub set_contact_emails ( $cpuser_obj, $old_addrs_ar, $new_addrs_ar ) {    ## no critic qw(ManyArg)
    if ( @$new_addrs_ar > 2 ) {
        die _invalidparamerr("Too many new addresses given!");
    }

    for my $specimen ( map { $_ // q<> } @$new_addrs_ar ) {
        if ( !Cpanel::Validate::EmailRFC::is_valid($specimen) ) {
            die _invalidparamerr("“$specimen” is not a valid email address.");
        }
    }

    my @real_olds = $cpuser_obj->contact_emails_ar()->@*;

    if ( @real_olds != @$old_addrs_ar || Cpanel::Set::difference( \@real_olds, $old_addrs_ar ) ) {
        die Cpanel::Exception::create_raw( 'Stale', 'Wrong old-address list', { addresses => \@real_olds } );
    }

    @{$cpuser_obj}{ 'CONTACTEMAIL', 'CONTACTEMAIL2' } = @$new_addrs_ar;

    return;
}

sub _invalidparamerr ($str) {
    return Cpanel::Exception::create_raw( 'InvalidParameter', $str );
}

1;
