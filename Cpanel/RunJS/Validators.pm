package Cpanel::RunJS::Validators;

# cpanel - Cpanel/RunJS/Validators.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::RunJS::Validators

=head1 SYNOPSIS

    my $js_validators = Cpanel::RunJS::Validators->new();

    # Validators often return functions.
    # Call that returned function to fetch the actual validation result.
    #
    my $errset = $js_validators->call('emailValidators.validateEmail')->(
        { value => 'foo@bar.com' },
    );

    if ($errset) {
        # Dig into $errset to see the problem.
    }
    else {
        # It’s valid.
    }

=head1 DESCRIPTION

This subclass of L<Cpanel::RunJS> runs cPanel’s C<@cpanel/validators>
module in Perl.

=head1 SEE ALSO

L<https://enterprise.cpanel.net/projects/CN/repos/validators/browse> is,
as of this writing, C<@cpanel/validators>’s canonical repository.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::RunJS';

use Cpanel::Imports;

use Cpanel::UTF8::Deep   ();
use Cpanel::UTF8::Strict ();

use constant _JS_GLOBALS => (
    _CP_LOCALE => {
        maketext => \&_my_make_text,
    },
);

#----------------------------------------------------------------------

=head1 METHODS

Besides methods inherited from L<Cpanel::RunJS>:

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    return $class->SUPER::new(
        '@cpanel/validators/dist/bundles/cpanel-validators.min.mjs',
    );
}

sub _AFTER_IMPORT ( $, $name ) {
    return qq<
        $name.BaseValidator.locale = _CP_LOCALE;
    >;
}

sub _my_make_text (@args) {

    # We can mutate @args since it only exists for Perl code to
    # receive data from JavaScript.
    @args = map { Cpanel::UTF8::Deep::encode($_) } @args;

    my $ret = locale()->makevar(@args);
    Cpanel::UTF8::Strict::decode($ret) if $ret;

    return $ret;
}

1;
