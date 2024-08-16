package Cpanel::Autodie::More;

# cpanel - Cpanel/Autodie/More.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module contains convenience-replacements for Perl built-ins.
# Its calls wrap Cpanel::Autodie to reap the benefits of that module.
#----------------------------------------------------------------------

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Autodie::More

=head1 DESCRIPTION

The functions in most Cpanel::Autodie::* modules C<die()> reproduce
core Perl behavior as exactly as possible (but with exceptions). Often
that behavior isn’t the most useful, however.

This module implements useful variants on the normal “autodie” behavior.
In situations where the expense of generating an exception is significant
this can be really helpful.

=head1 REPLACEMENT FOR C<stat()>-based checks

It is probably best to avoid a “pre-C<stat()>” like the following:

    if (!-d $path) {
        mkdir($path);
    }

… because the filesystem state could change between the C<stat()> (i.e.,
the C<-d> check) and the C<mkdir()>. Also, a falsey return from C<-d>
doesn’t necessarily mean that C<$path> doesn’t exist; any error at all
from the C<stat()> actually causes the falsey return, which can include
anything that C<man 2 stat> describes.

Several of this module’s functions
fix this behavior while still C<die()>ing when there
is a “real” error. For example, the following code:

    Cpanel::Autodie::More::mkdir_if_not_exists($path);

… has three advantages over the prior example:

=over

=item 1) It solves the race safety problem.

=item 2) It solves the falsey-C<-d> problem.

=item 3) It’s only one disk operation in the success case, so it’s
faster in the creation case. (It may be marginally slower if the
directory already exists.)

=back

=head1 FUNCTIONS

=cut

use Try::Tiny;

# Can’t use Cpanel::Autodie’s normal import() mechanism because
# perlpkg doesn’t interact with that very well. So we have to load
# the CORE::* modules directly.
use Cpanel::Autodie                               ();
use Cpanel::Autodie::CORE::mkdir                  ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::mkdir_if_not_exists    ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::link                   ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::rename_if_exists       ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::unlink_if_exists       ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::link_if_no_conflict    ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::symlink_if_no_conflict ();    # PPI USE OK - reload so we can map the symbol below

# Umask::Local cannot be used here because
# this module gets fatpacked into upcp.static
use Cpanel::Umask ();

use constant {
    _ENOENT => 2,
    _EEXIST => 17,
};

#“politely”, i.e., won’t clobber an already-existing node.
sub rename_nondir_politely {
    my ( $old, $new ) = @_;

    local ( $!, $@ );
    require Cpanel::CommandQueue;

    my $q = Cpanel::CommandQueue->new();

    #First link the old path to the new.
    $q->add(
        sub { Cpanel::Autodie::link( $old, $new ) },
        sub { Cpanel::Autodie::unlink_if_exists($new) },
        'unlink new path',
    );

    #Now unlink the old path.
    $q->add(
        sub { Cpanel::Autodie::unlink_if_exists($old) },
    );

    $q->run();

    return;
}

#----------------------------------------------------------------------
# mkdir()
# mkdir( PATH )
# mkdir( PATH, REALPERMS )
#
#Just like Cpanel::Autodie::mkdir(), except:
#
#   - REALPERMS is “real” perms, not a bitmask as in Perl’s built-in.
#       If not given, this defaults to whatever perms built-in mkdir()
#       will assign to the new directory.
#
sub mkdir {
    my (@args) = @_;

    my $umask;

    if ( @args > 1 ) {
        $umask = Cpanel::Umask->new(0);
    }

    return Cpanel::Autodie::mkdir(@args);
}

#Just like this module’s mkdir() except it will not error if the given
#filesystem path is already in use. NOTE: To preserve race safety, this
#does NOT error if the given path exists but is not a directory!
#
sub mkdir_if_not_exists {
    my (@args) = @_;

    my $umask = ( @args > 1 ) && Cpanel::Umask->new(0);

    return Cpanel::Autodie::mkdir_if_not_exists(@args);
}

#----------------------------------------------------------------------

*rename_if_exists = *Cpanel::Autodie::rename_if_exists;

=head2 $linked = link_if_no_conflict( OLDNAME => NEWNAME )

=over

=item * Returns 1 if the link succeeds.

=item * Returns 0 if the link fails because of EEXIST (i.e., the NEWNAME
path already exists).

=item * C<die()>s otherwise with L<Cpanel::Exception::IO::LinkError>

=back

=cut

*link_if_no_conflict = \*Cpanel::Autodie::link_if_no_conflict;

#----------------------------------------------------------------------

=head2 symlink_if_no_conflict( OLDNAME => NEWNAME )

Same as C<link_if_no_conflict()> but uses C<symlink()> underneath
rather than C<link()>. The exception that’s thrown is an instance of
L<Cpanel::Exception::IO::SymlinkCreateError>.

=cut

*symlink_if_no_conflict = \*Cpanel::Autodie::symlink_if_no_conflict;

#
# **** WARNING The Let’s Encrypt Plugin relies on this function
# **** WARNING existing (Cpanel::Autodie::More::unlink_if_exists).
#
*unlink_if_exists = *Cpanel::Autodie::unlink_if_exists;

1;
