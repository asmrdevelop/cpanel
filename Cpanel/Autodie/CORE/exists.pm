package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/exists.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 FUNCTIONS

=head2 $yn = exists( $PATH )

Perl’s C<-e> test doesn’t distinguish ENOENT from, say, EACCES; i.e., a
falsy return could mean the node doesn’t exist, or it could mean that
something prevents us from knowing whether the file exists. C<-e> doesn’t
indicate “does it exist?” so much as “can I confirm that it exists?”.
Quite often, the difference is important enough to be fatal.

This fixes that by treating any OS error besides ENOENT
as a failure to determine the question of the path’s existence, and thus
a fatal condition. This is, thus, a proper existence check: it answers
the question of whether the node exists, or it “C<die()>s” in the attempt.

B<NOTE:> This does, usefully, populate the special C<_> file handle.

You can thus do things like:

   exists('/path/to') && -d _

… to get an error-checked C<-d>, or any other C<stat()>-based check.

=cut

sub exists {    ## no critic qw( RequireArgUnpacking )
    local ( $!, $^E );

    if ( ${^GLOBAL_PHASE} eq 'START' ) {
        _die_err( $_[0], "do not access the filesystem at compile time" );
    }

    return 1 if -e $_[0];
    return 0 if $! == _ENOENT();

    return _die_err( $_[0], $! );
}

=head2 $yn = exists_nofollow( $PATH )

Like C<exists()> but uses an C<lstat()> underneath to avoid following
$PATH if it’s a symlink. Note that this doesn’t prevent following symlinks
earlier in $PATH than the end node.

=cut

sub exists_nofollow {
    my ($path) = @_;

    #NOTE: Avoid try/catch here to minimize overhead.

    local ( $!, $^E );

    return 1 if CORE::lstat $path;

    return 0 if $! == _ENOENT();

    return _die_err( $path, $! );
}

sub _die_err {
    my ( $path, $err ) = @_;

    local $@;    # $! is already local()ed.
    require Cpanel::Exception;

    die Cpanel::Exception::create( 'IO::StatError', [ error => $err, path => $path ] );
}

1;
