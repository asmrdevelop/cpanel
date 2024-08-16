package Cpanel::LinkedNode::UniquenessToken;

# cpanel - Cpanel/LinkedNode/UniquenessToken.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::UniquenessToken

=head1 SYNOPSIS

    my $token = Cpanel::LinkedNode::UniquenessToken::create_and_write();

    # Returns falsy to indicate that $token already exists.
    Cpanel::LinkedNode::UniquenessToken::write($token);

    # Returns truthy to indicate that the given token was written.
    Cpanel::LinkedNode::UniquenessToken::write('something_else');

=head1 DESCRIPTION

This module facilitates detection of whether a given node is the same as
one or more others. It maintains a datastore of unique tokens; if the token
already exists, then a follow-up write of that same token will be detectable
and indicate non-uniqueness.

On node A, do:

    my $token = Cpanel::LinkedNode::UniquenessToken::create_and_write();

… then, on node B, do:

    if ( Cpanel::LinkedNode::UniquenessToken::write($token) ) {
        # nodes are different
    }
    else {
        # nodes are the same
    }

Note that, if you have node C as well, you can repeat the steps for node B
to verify that node C is different from both node A and node B. Likewise
with node D, etc.

=head1 DATASTORE CLEANUP

Each successful write to the datastore enqueues a server
task to delete the datastore entry after a suitable period.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie          ();
use Cpanel::Fcntl::Constants ();
use Cpanel::ServerTasks      ();
use Cpanel::Try              ();

# Accessed from tests
our $_BASE;

BEGIN {
    $_BASE = '/var/cpanel/uniqueness';
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $token = create_and_write()

Generates a random token, saves it to the datastore, then returns the token.

The token will always be alphanumeric: a-z, A-Z, 0-9, and _

=cut

sub create_and_write {
    require Cpanel::Rand::Get;
    my $token = Cpanel::Rand::Get::getranddata(32);

    return __PACKAGE__->can('write')->($token) && $token;
}

=head2 $wrote = write($TOKEN)

Writes a given $TOKEN to the datastore. $TOKEN should have come from a
call to C<create_and_write()>.

The return is a boolean: truthy if the token was written, falsy if the token
already exists in the datastore. (On any other condition an exception is
thrown.)

=cut

sub write ($token) {
    die 'invalid token' if $token =~ tr<a-zA-Z0-9_><>c;

    _ensure_dir();

    my $path = "$_BASE/$token";

    my $created;

    # The exception is unoptimized, but failure cases should be rare anyway.
    Cpanel::Try::try(
        sub {
            my $fh;

            Cpanel::Autodie::sysopen(
                $fh,
                $path,
                $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_EXCL,
                0600,
            );

            $created = 1;
        },
        'Cpanel::Exception::IO::FileOpenError' => sub {
            my $err = $@;

            if ( $err->error_name() ne 'EEXIST' ) {
                local $@ = $err;
                die;
            }
        },
    );

    if ($created) {
        Cpanel::ServerTasks::schedule_task( ['ScriptTasks'], 3600, "run_script rm -f $path" );

        return 1;
    }

    return 0;
}

sub _ensure_dir {
    Cpanel::Autodie::mkdir_if_not_exists( $_BASE, 0700 ) or do {
        Cpanel::Autodie::chmod( 0700, $_BASE );
    };

    return;
}

1;
