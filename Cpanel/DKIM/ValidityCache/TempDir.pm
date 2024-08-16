package Cpanel::DKIM::ValidityCache::TempDir;

# cpanel - Cpanel/DKIM/ValidityCache/TempDir.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DKIM::ValidityCache::TempDir

=head1 SYNOPSIS

    my $tempdir = Cpanel::DKIM::ValidityCache::TempDir->new();

    $tempdir->install();

=head1 DESCRIPTION

An instance of this class represents a temporary override
of the global location for the DKIM validity cache’s on-disk location.
It’s useful for initializing the validity cache.

=cut

#----------------------------------------------------------------------

use Cpanel::DKIM::ValidityCache ();

use constant {
    _ENOENT    => 2,
    _EEXIST    => 17,
    _ENOTEMPTY => 39,
};

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 I<CLASS>->new()

Sets the validity cache to use a temporary directory. Returns a
class instance. When the object is DESTROYed, the validity cache
will go back to the main path.

=cut

sub new {
    my ($class) = @_;

    my $old = $Cpanel::DKIM::ValidityCache::BASE_DIRECTORY;

    $Cpanel::DKIM::ValidityCache::BASE_DIRECTORY .= sprintf( ".$$.%d.%d", time, substr( rand, 2 ) );

    return bless \$old, $class;
}

#----------------------------------------------------------------------

=head2 $changed_yn = I<OBJ>->install()

C<rename()>s the temporary directory into place. If this is not called
prior to the object’s DESTROY, a warning is thrown.

If the directory is moved into place, 1 is returned. If the temporary
directory doesn’t exist, or if the target directory exists and is not empty,
then 0 is returned. Any other status prompts a thrown exception.

=cut

sub install {
    my ($self) = @_;

    die "Already installed!" if !$$self;

    my $tempdir = $Cpanel::DKIM::ValidityCache::BASE_DIRECTORY;
    my $maindir = $$self;

    $self->_restore_basedir();

    my $ret = rename( $tempdir => $maindir ) or do {

        # Unfortunately, EEXIST is overloaded here such that we can’t
        # distinguish between a failure to clobber a nonempty directory
        # and a failure to overwrite a non-directory node.
        if ( $! != _ENOENT() && $! != _ENOTEMPTY() && $! != _EEXIST() ) {
            die "rename($tempdir => $maindir): $!";
        }

        0;
    };

    return $ret;
}

sub DESTROY {
    my ($self) = @_;

    if ($$self) {
        warn "$self: DESTROYed but not install()ed!";

        $self->_restore_basedir();
    }

    return;
}

sub _restore_basedir {
    my ($self) = @_;

    $Cpanel::DKIM::ValidityCache::BASE_DIRECTORY = $$self;

    $$self = undef;

    return;
}

1;
