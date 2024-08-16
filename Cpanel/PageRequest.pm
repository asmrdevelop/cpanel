#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/PageRequest.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::PageRequest;

use strict;
use warnings;

use Cpanel::Rand::Get ();
use Cpanel::JSON      ();
use Cpanel::Locale 'lh';
use Fcntl;

=head1 NAME

Cpanel::PageRequest

=head1 DESCRIPTION

Cpanel::PageRequest provides a simple OO interface to a session storage.

=head1 SYNOPSIS

    my $req = Cpanel::PageRequest->new(
        path => $session_file,
        data => { favorite_color => 'red' }
    );
    $req->save_session();

    give_cookie_to_browser($req->cookie);

    ...

    if ( $req->is_token_mismatched($cookie_sent_back_from_browser) ) {
        die q{You didn't send back the cookie I gave you. Are you really the same person?};
    }
    else {
        proceed_with_task();
    }

=cut

=head1 CONSTRUCTION

=head2 new(PROPS)

=head3 Arguments

    - hash - The attributes of the object to be constructed
        - path - string - (Required) The absolute path to the session storage file.
                          This must be unique for each distinct session, and the caller
                          is responsible for ensuring uniqueness.
        - data - hash ref - (Optional) Any extra data you want to be stored as part
                            of the session. It will be available again when the session
                            is loaded.
        - unlink_invalid - boolean - (Optional) if true, will remove any bad session files.
                                    otherwise, will leave them in place. By default it cleans
                                    them up.

=cut

sub new {
    my ( $class, %props ) = @_;

    if ( !$props{path} ) {
        die 'You must specify a path for the session storage file.';
    }

    my $self = {
        data           => {},
        unlink_invalid => 1,
        (%props),
    };

    bless $self, $class;

    $self->new_cookie();

    return $self;
}

=head1 METHODS

=head2 load_session()

=head3 Purpose

Reads a previously stored page request token and application-specific
data structure (JSON blob). These are stored in the object 'cookie' and
'data' properties.

=head3 Arguments

n/a

=head3 Returns

n/a

=cut

sub load_session {
    my $self = shift;
    if ( !$self->{path} || !-f $self->{path} ) {
        $self->{_loaded_from_disk} = 1;
        return;
    }

    if ( open my $ps_fh, '<', $self->{path} ) {
        chomp( my $stored_properties = readline($ps_fh) );

        # Tab-delimited data preserves compatibility with existing cookie-only format
        my ( $cookie, $timestamp ) = split /\t/, $stored_properties;

        # If the session file is expired, delete it, and treat it as if it hadn't existed to begin with
        if (   $timestamp
            && $self->{max_age}
            && ( time() - $timestamp ) > $self->{max_age} ) {
            $self->unlink();
            $self->{_loaded_from_disk} = 1;
            return;
        }

        my $data = do {
            local $/;
            readline($ps_fh);
        };
        close $ps_fh;
        $self->{cookie} = $cookie;
        my $parsed = eval { Cpanel::JSON::Load( $data || '' ) };
        if ( my $exception = $@ ) {
            $self->{_failed_to_load} = 1;             # Flag it so someone who is interested can look at it.
            $self->{_exception}      = $exception;    # And the reason if failed.
            unlink $self->{path} if $self->{unlink_invalid};
        }
        else {
            $self->{data} = $parsed;
        }
        $self->{_loaded_from_disk} = 1;
    }

    return;
}

=head2 save_session()

=head3 Purpose

Writes the reset token name to the file system for later use in comparison against
the value submitted by the user on the next step. This acts as a light weight page
level validation of the request.

=head3 Arguments

n/a

=head3 Returns

n/a

=cut

sub save_session {
    my $self = shift;
    return 0 if !$self->{path};

    if ( sysopen( my $ps_fh, $self->{path}, Fcntl::O_WRONLY() | Fcntl::O_TRUNC() | Fcntl::O_CREAT(), 0600 ) ) {
        print {$ps_fh} sprintf( "%s\t%s\n", $self->{cookie}, $self->{timestamp} || time() );
        print {$ps_fh} Cpanel::JSON::Dump( $self->{data} );
        close($ps_fh);
    }
    return 1;
}

=head2 is_token_mismatched(COOKIE)

=head3 Purpose

Helper to check that the token passed from the request matches the one previously stored
on the server.

=head3 Arguments

COOKIE - string - cookie provided with the request submitting the user's password.

=head3 Returns

boolean - truthy if there is a mismatch. falsy otherwise.

=cut

sub is_token_mismatched {
    my ( $self, $cookie ) = @_;
    $self->load_session();

    my $bad_cookie =
         !$self->{cookie}
      || !$cookie
      || $self->{cookie} ne $cookie;

    return $bad_cookie ? 1 : 0;
}

=head2 cookie()

=head3 Purpose

Read-only accessor for the 'cookie' attribute.

This token/cookie should be sent to the client, and it should be verified
on the next request using is_token_mismatched.

=head3 Arguments

n/a

=head3 Returns

string - The string to be used for the session cookie.

=cut

sub cookie {
    my ($self) = @_;
    $self->_load_if_needed();
    return $self->{cookie};
}

=head2 new_cookie()

=head3 Purpose

Regenerate the cookie. This may be used to force the user along an exact sequence
of actions, requiring a different cookie to be provided for each step.

The new cookie is stored in the object and returned. It may be saved by calling
save_session().

Any other data stored as part of the session will be preserved.

=head3 Arguments

n/a

=head3 Returns

string - The new cookie

=cut

sub new_cookie {
    my ($self) = @_;
    return $self->{cookie} = Cpanel::Rand::Get::getranddata(16);
}

=head2 data(DATA)

=head3 Purpose

Read-only accessor for the 'data' attribute.

=head3 Arguments

    DATA - reference to the data to store.

=head3 Returns

    hash ref - The data that was loaded from disk. If it has not been loaded yet,
               it will be loaded on demand.

=cut

sub data {
    my ( $self, $data ) = @_;
    $self->_load_if_needed();
    $self->{data} = $data if $data;
    return $self->{data};
}

=head2 unlink()

=head3 Purpose

Removes the backing file for the session

=head3 Arguments

n/a

=head3 Returns

n/a

=cut

sub unlink {
    my ($self) = @_;
    if ( -e $self->{path} ) {
        unlink $self->{path};
    }
    return;
}

sub _load_if_needed {
    my ($self) = @_;
    if ( !$self->{_loaded_from_disk} ) {
        $self->load_session();
    }
    return;
}

1;
