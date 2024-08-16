package Cpanel::CLI::SecretTaker;

# cpanel - Cpanel/CLI/SecretTaker.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CLI::SecretTaker

=head1 DESCRIPTION

This module houses common logic for scripts that need to accept a secret
as input.

=cut

#----------------------------------------------------------------------

use IO::Prompter ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $secret = I<OBJ>->get_secret( $PROMPT, @OPTS )

Displays $PROMPT and solicits input of a secret text
(i.e., a password or passphrase).

%OPTS are given to the underlying C<IO::Prompter::prompt()> call.
See that function’s documentation for the relevant options.

=cut

sub get_secret ( $, $prompt, @opts ) {
    my $val;

    while ( !length $val ) {
        $val = IO::Prompter::prompt(
            $prompt,
            -stdio,
            -echo => q<>,
            @opts,
        );
    }

    return $val;
}

1;
