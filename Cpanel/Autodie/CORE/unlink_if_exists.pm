package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/unlink_if_exists.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 unlink_if_exists( $PATH )

Like C<unlink()> but will not throw on ENOENT.

This is probably more useful than C<unlink()> since there are
very few cases where ENOENT should be a fatal error for this function.

Also see L<Cpanel::Autowarn> for a similar implementation but with
warnings rather than exceptions.

=cut

#Like Cpanel::Autodie::unlink() except:
#   - won’t complain if the path doesn’t exist
#
#Returns 1 if a file was deleted, or 0 if not.
#
sub unlink_if_exists {
    my (@args) = @_;

    die "At most 1 parameter!" if @args > 1;

    my $ret = 0;

    #So, technically, this makes the function’s name a misnomer since
    #this always attempts the unlink() regardless of whether the node
    #exists. The difference, though, is transparent to the user, and,
    #more importantly, we avoid TOCTTOU errors.
    local ( $!, $^E );

    my $path = @args ? $args[0] : $_;
    $ret = CORE::unlink($path);

    if ( $! && $! != _ENOENT() ) {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::UnlinkError', [ error => $err, path => [$path] ] );
    }

    return $ret;
}

1;
