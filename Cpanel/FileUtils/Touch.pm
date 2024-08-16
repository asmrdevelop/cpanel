package Cpanel::FileUtils::Touch;

# cpanel - Cpanel/FileUtils/Touch.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# NB: Can’t use signatures because of perlpkg.

=encoding utf-8

=head1 NAME

Cpanel::FileUtils::Touch - Create a touch file

=head1 SYNOPSIS

    my $is_new = Cpanel::FileUtils::Touch::touch('/path/to/file');

=head1 DESCRIPTION

This is a partial replacement for L<Cpanel::FileUtils::TouchFile>.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Autodie;
use Cpanel::Fcntl;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $created_yn = touch_if_not_exists( $PATH )

Creates $PATH if it doesn’t already exist.
Returns a boolean that indicates whether the $PATH is newly-created.

NB: In contrast to L<touch(1)>, this will B<NOT> update any timestamps
of an existing file.

(You can use the above to provide logic analogous to
L<Cpanel::Autodie>’s C<unlink_if_exists()> function.)

Errors prompt thrown L<Cpanel::Exception> objects.

=cut

sub touch_if_not_exists {
    my ($path) = @_;

    my $fh;

    # Ideally we should make this not instantiate a Cpanel::Exception
    # object when we get EEXIST, but for now this is how it’s written:

    try {

        # NB: There’s no point in specifying a mode here because
        # a touch file is, by definition, empty.
        Cpanel::Autodie::sysopen(
            $fh,
            $path,
            Cpanel::Fcntl::or_flags(qw( O_WRONLY  O_CREAT  O_EXCL )),
        );
    }
    catch {
        undef $fh;

        if ( !try { $_->error_name() eq 'EEXIST' } ) {
            local $@ = $_;
            die;
        }
    };

    return $fh ? 1 : 0;
}

1;
