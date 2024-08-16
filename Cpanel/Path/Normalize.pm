package Cpanel::Path::Normalize;

# cpanel - Cpanel/Path/Normalize.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Path::Normalize

=head1 SYNOPSIS

    my $pure_path = Cpanel::Path::Normalize::normalize($given_path);

=head1 FUNCTIONS

=head2 normalize( PATH )

Similar to C<Cwd::abs_path()> but doesn’t resolve symbolic links.

Note that if PATH is an absolute path, then leading C</..> is reduced
to just C</>. While it’s debatable that this should be an error condition,
since the kernel accepts it there’s justification for the present behavior.

=cut

sub normalize {
    my $uncleanpath = shift || return;

    my $is_abspath = ( 0 == index( $uncleanpath, '/' ) );

    my @pathdirs = split( m[/], $uncleanpath );

    my @cleanpathdirs;
    my $leading_dot_dots = 0;

    # Check ".." and recalc path.
    foreach my $dir (@pathdirs) {
        next if !length $dir;    #Remove extraneous "//" and leading "/"

        #discard “.”
        next if $dir eq '.';

        if ( $dir eq '..' ) {
            if (@cleanpathdirs) {
                pop(@cleanpathdirs);
            }
            else {
                $leading_dot_dots++;
            }
        }
        else {
            push( @cleanpathdirs, $dir );
        }
    }

    if ($is_abspath) {
        return ( '/' . join( '/', @cleanpathdirs ) );
    }

    unshift @cleanpathdirs, ('..') x $leading_dot_dots;

    return join( '/', @cleanpathdirs );
}

=head1 SEE ALSO

L<Cpanel::Validate::FilesystemPath> will reject absolute paths with
leading C</..>.

=cut

1;
