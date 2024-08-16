package Cpanel::Exception::Base::HasUrl;

# cpanel - Cpanel/Exception/Base/HasUrl.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::Base::HasUrl

=head1 SYNOPSIS

See subclasses

=head1 DESCRIPTION

This L<Cpanel::Exception> subclass includes a couple of methods for exceptions
that include a C<uri> property.

=head1 METHODS

=cut

use strict;
use warnings;

#accessed from tests
our $_STACK_TRACE_SUBSTITUTION = '__CPANEL_URLPW_HIDDEN__';

use parent qw( Cpanel::Exception );

use Cpanel::URI::Password ();

=head2 I<OBJ>->get_url_without_password()

This stubs out a dummy password text in place of the password that the
exception’s C<url> already contains. (Of course, if C<url> contains no
password, then this is identical to just C<get()>ting the C<url>.)

=cut

sub get_url_without_password {
    my ($self) = @_;
    my $url = $self->get('url');

    # Avoid undefined values warnings by checking this first.
    return undef unless defined $url;
    return Cpanel::URI::Password::strip_password($url);
}

=head2 I<OBJ>->longmess()

Overrides the L<Cpanel::Exception> default method of the same name to
replace any instances of the URL password with a dummy text. (If
there’s no password in C<url>, then this is identical to the overridden
method.)

=cut

sub longmess {
    my ($self) = @_;

    my $mess = $self->SUPER::longmess();
    my $url  = $self->get('url');

    if ( defined $url && ( my $passwd = Cpanel::URI::Password::get_password($url) ) ) {
        $mess =~ s<\Q$passwd\E><$_STACK_TRACE_SUBSTITUTION>g;
    }

    return $mess;
}

1;
