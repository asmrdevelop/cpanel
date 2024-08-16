package Cpanel::Exception::GenericForUser;

# cpanel - Cpanel/Exception/GenericForUser.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::GenericForUser

=head1 SYNOPSIS

    die Cpanel::Exception::create('GenericForUser')->set_id($internal_xid);

=head1 DISCUSSION

This is useful when you want to tell a user about an error that may require
support intervention but don’t B<actually> want to give details about it.

Note how the SYNOPSIS demonstrates setting an ID. This is probably a good idea
so that that a support technician can correlate the user’s reported error with
a log message.

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'An error occurred. If this persists, contact your support representative.',
    );
}

1;
