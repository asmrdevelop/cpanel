package Cpanel::FileUtils::WriteLink;

# cpanel - Cpanel/FileUtils/WriteLink.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::FileUtils::WriteLink

=head1 SYNOPSIS

    Cpanel::FileUtils::WriteLink::overwrite( $destination, $path );

=head1 DESCRIPTION

This module exposes tools that parallel those for L<Cpanel::FileUtils::Write>
but for symbolic links instead of regular files.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie ( 'symlink', 'rename' );
use Cpanel::Autowarn ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 overwrite( $OLDNAME, $NEWNAME )

Like the C<symlink()> built-in but writes to a temp path first then
rename()s into place. Thus, any existing symlink B<OR> B<NODE> B<OF>
B<OTHER> B<TYPE> (e.g., a regular file) will be overwritten.

Any error along the way will trigger a thrown L<Cpanel::Exception>.

Returns nothing.

=cut

sub overwrite ( $oldname, $newname ) {
    my $temp_path     = $newname;
    my $last_slash_at = rindex( $temp_path, '/' );

    my $salt = substr( rand, 2 );
    my $now  = time;
    $_ = sprintf '%x', $_ for ( $salt, $now );
    substr( $temp_path, 1 + $last_slash_at, 0, ".tmp.$now.$salt." );

    local $@;
    Cpanel::Autodie::symlink( $oldname, $temp_path );

    eval { Cpanel::Autodie::rename( $temp_path, $newname ) } or do {
        my $err = $@;
        Cpanel::Autowarn::unlink($temp_path);

        local $@ = $err;
        die;
    };

    return;
}

1;
