package Cpanel::SMTP::Singleton;

# cpanel - Cpanel/SMTP/Singleton.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SMTP::Singleton - cached SMTP connection

=head1 SYNOPSIS

    my $smtp = Cpanel::SMTP::Singleton::localhost( 'skroob', '12345-luggage' );

    # This will reuse the same connection.
    $smtp2 = Cpanel::SMTP::Singleton::localhost( 'skroob', '12345-luggage' );

    # This will open a new connection and authenticate as the new user.
    # (SMTP doesn’t allow reuse of the same connection for two users.)
    $smtp2 = Cpanel::SMTP::Singleton::localhost( 'lonestar', 'winnebago' );

    # This will recreate the connection without authentication.
    my $smtp = Cpanel::SMTP::Singleton::localhost();

=head1 DESCRIPTION

This module provides a singleton cache of an SMTP connection. It’s useful
for when you send many messages over SMTP using the same authentication.
It determines when a connection can be reused and when it needs to be
reset.

The reuse rules that this module follows are:

=over

=item * An authenticated connection is reused if and only if the reuse
uses the same authentication credentials.

=item * An unauthenticated connection is always reused. If the reuse
uses authentication, the connection takes on those credentials and follows
the logic described in the previous rule.

=back

This would be much simpler if SMTP’s C<RSET> command affected
authentication, but it doesn’t.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Destruct ();
use Cpanel::SMTP     ();

our $SMTP_TIMEOUT = 30;    # must be at least long enough for spamassassin to scan an outgoing message

# Retry is supported, but since we just fall back to sendmail
# we don’t bother.
our $SMTP_MAX_CONNECTION_ATTEMPTS = 1;

# Accessed from tests.
our $_SMTP_SINGLETON;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 localhost( $USERNAME, $PASSWORD )

Returns a L<Cpanel::SMTP> instance with a connection to the SMTP server
running on the loopback interface. $USERNAME and $PASSWORD are
only needed when authenticating; if they are given, the returned object
will be authenticated.

An appropriate exception is thrown if any error happens.

=cut

sub localhost {
    my ( $un, $pw ) = @_;

    if ( _should_reuse_smtp_singleton( $un, $pw ) ) {
        try {
            $_SMTP_SINGLETON->reset();
        }
        catch {
            # likely disconnected due to idle
            undef $_SMTP_SINGLETON;
        };
    }

    _ensure_smtp_connection('127.0.0.1');

    if ( $un && !$_SMTP_SINGLETON->auth_username() ) {
        $_SMTP_SINGLETON->auth( $un, $pw );
    }

    return $_SMTP_SINGLETON;
}

#----------------------------------------------------------------------

=head2 close()

Closes any connection that this module may be holding.

=cut

sub close {
    if ($_SMTP_SINGLETON) {
        local $@;
        eval { $_SMTP_SINGLETON->quit(); 1 } or warn;

        undef $_SMTP_SINGLETON;
    }

    return;
}

#----------------------------------------------------------------------

# truthy iff we will reuse a connection
sub _should_reuse_smtp_singleton {
    my ( $username, $password ) = @_;

    # Can’t reuse what’s not there!
    return 0 if !$_SMTP_SINGLETON;

    # If we previously authenticated, then only reuse the connection
    # if it’s for the same user.
    if ( my $previous_un = $_SMTP_SINGLETON->auth_username() ) {
        if ( $previous_un ne ( $username // q<> ) ) {
            undef $_SMTP_SINGLETON;
            return 0;
        }
    }

    # We got here because:
    #   - previous authentication matches the $username, OR …
    #   - there is no previous authentication

    return 1;
}

sub _ensure_smtp_connection {
    my ($smtp_host) = @_;

    if ( !$_SMTP_SINGLETON ) {
        my $err;
        for my $attempt ( 1 .. $SMTP_MAX_CONNECTION_ATTEMPTS ) {
            _sleep($SMTP_TIMEOUT) if $attempt > 1;

            try {
                $_SMTP_SINGLETON = Cpanel::SMTP->new( $smtp_host, Timeout => $SMTP_TIMEOUT );
            }
            catch {
                $err = $_;
            };

            if ($_SMTP_SINGLETON) {
                return $_SMTP_SINGLETON;
            }

        }

        local $@ = $err;
        die;

    }

    return $_SMTP_SINGLETON;
}

sub _sleep {
    return sleep(@_);
}

END {
    if ( !Cpanel::Destruct::in_dangerous_global_destruction() ) {
        __PACKAGE__->can('close')->();
    }
}

1;
