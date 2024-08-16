package Cpanel::Validate::UserNote;

# cpanel - Cpanel/Validate/UserNote.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Imports;
use Cpanel::RunJS::Validators ();

=encoding utf-8

=head1 NAME

Cpanel::Validate::UserNote

=head1 SYNOPSIS

    my $err = Cpanel::Validate::UserNote::why_invalid("Some string to validate");
    die $err if $err;

=head1 DESCRIPTION

This validator defines and validates a cPanel-specific format that
encompasses those characters we think a reasonable user would use to
write a “note to self” about some object, e.g., an email account or
a team member.

=head2 $err = why_invalid( $NOTE )

$NOTE B<MUST> be a valid UTF-8 byte string. It’s validated
further via the cPUserNote validation in the @cpanel/validators TypeScript
library.

Returns a translated error string that explains why $NOTE is invalid.

=cut

sub why_invalid ($note) {
    if ($note) {
        my $validator = Cpanel::RunJS::Validators->new();
        my $got       = $validator->call('cPUserNoteValidators.validate')->($note);
        if ($got) {
            my $err = ( values %$got )[0]{'message'};
            return locale()->maketext( 'The given comment is invalid: [_1]', $err );
        }
    }

    return undef;
}

1;
