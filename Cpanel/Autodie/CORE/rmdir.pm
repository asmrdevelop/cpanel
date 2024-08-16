package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/rmdir.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 rmdir($PATH)

cf. L<perlfunc/rmdir>

=cut

sub rmdir {
    my (@args) = @_;

    local ( $!, $^E );

    return _rmdir_if_exists(@args) || _die_rmdir( $args[0], $! );
}

=head2 rmdir_if_exists()

Like C<rmdir()> but will return undef on ENOENT
rather than throwing an exception.

=cut

sub rmdir_if_exists {
    my (@args) = @_;

    local ( $!, $^E );

    return _rmdir_if_exists(@args);
}

sub _rmdir_if_exists {
    my (@args) = @_;

    #Perl's rmdir() doesn't actually allow batching like this,
    #but we might as well prevent anyone from trying.
    die "Only one path at a time!" if @args > 1;

    my $path = @args ? $args[0] : $_;

    return CORE::rmdir($path) || do {
        return 0 if $! == _ENOENT();

        return _die_rmdir( $path, $! );
    };
}

sub _die_rmdir {
    my ( $path, $err ) = @_;

    local $@;
    require Cpanel::Exception;

    die Cpanel::Exception::create( 'IO::DirectoryDeleteError', [ error => $err, path => $path ] );
}

1;
