package Cpanel::ContactInfo::Email;

# cpanel - Cpanel/ContactInfo/Email.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::ContactInfo::Email - Email-related logic

=head1 SYNOPSIS

    my @emails = split_multi_email_string('foo@bar.com , baz@qux.org');

=head1 DESCRIPTION

This module used to contain the “legacy” contact email implementation
(F<~/.contactemail>), but since v106 removed that logic it now just
contains a bit of associated, still-useful stuff.

=cut

#----------------------------------------------------------------------

use Cpanel::Context            ();
use Cpanel::Validate::EmailRFC ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @addresses = split_multi_email_string( $EMAILS_STRING )

Splits a string that contains multiple email addresses. Either a
comma or semicolon may join the addresses, and whitespace between addresses
is ignored.

For historical reasons, leading/trailing whitespace are I<NOT> removed;
instead, those outer addresses will be omitted from the result. (This is
I<probably> a bug, but as of this writing it’s retained.)

This function B<MUST> be called in list context.

=cut

sub split_multi_email_string ($email_string) {
    Cpanel::Context::must_be_list();

    my @addr;

    if ( length $email_string ) {
        for my $email ( split m/\s*[;,]+\s*/, $email_string ) {
            if ( Cpanel::Validate::EmailRFC::is_valid_remote($email) ) {
                push @addr, $email;
            }
        }
    }

    return @addr;
}

1;
