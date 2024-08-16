package Cpanel::Template::Plugin::CPOS;

# cpanel - Cpanel/Template/Plugin/CPOS.pm           Copyright 2022 cPanel, L.L.C.
#                                                            All rights Reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::CPOS - Template Toolkit plugin for Cpanel::OS

=head1 SYNOPSIS

    [% use CPOS %]

    [% IF Cpanel::OS::check_eq( 'sudoers', 'wheel' ) %]
        [%# Do something special on debian distro %]
    [% END %]

=cut

use parent 'Template::Plugin';

use Cpanel::OS ();    # PPI USE OK -- used just after

=head2 new

Constructor

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<SCALAR>

A new C<Cpanel::Template::Plugin::CPOS> object

=back

=back

=cut

sub new {
    return bless {}, $_[0];
}

=head2 check_eq($self, $key, $value)

Check any Cpanel::OS value using a string equality check

    Cpanel::OS::check_eq( 'base_distro', 'rhel' );

=over 2

=item Input

=over 3

=item KEY C<SCALAR>

The Cpanel::OS::KEY() we want to check

=item VALUE C<SCALAR>

The expected VALUE we want to check.

=back

=item Output

=over 3

Returns a boolean: 1/0. True when the equality matches.

=back

=back

=cut

sub check_eq ( $self, $key, $value ) {    # cpanel_os_check
    my $current = eval qq[ Cpanel::OS::$key() ] // '';    ## no critic qw(ProhibitStringyEval)

    return $current eq $value ? 1 : 0;
}

1;
