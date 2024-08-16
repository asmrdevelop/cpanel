package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/mkdir.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use File::Path                         ();
use Cpanel::Validate::OctalPermissions ();

=head1 FUNCTIONS

=head2 mkdir( $PATH, $MODE )

cf. L<perlfunc/mkdir>

=cut

sub mkdir ( $dir, $mode = undef ) {
    local ( $!, $^E );

    $mode = _normalize_mode($mode) if defined $mode;
    my $return = _mkdir_list( $dir, $mode );

    if ( !$return ) {
        _die_for_mkdir( $dir, $mode );
    }

    return $return;
}

=head2 mkpath( $PATH, $MODE)

cf. L<perlfunc/make_path>

=cut

sub mkpath ( $dir, $mode = undef ) {
    local ( $!, $^E );

    $mode = _normalize_mode($mode) if defined $mode;
    my $return = _mkpath_list( $dir, $mode );

    if ($return) {
        _die_for_mkdir( $dir, $mode );
    }

    return $return;
}

local *make_path = \&mkpath;

=head2 mkdir_if_not_exists( $PATH, $MODE )

Like C<mkdir()> but will return undef on ENOENT instead
of throwing an exception.

=cut

sub mkdir_if_not_exists ( $dir, $mode = undef ) {
    local ( $!, $^E );

    $mode = _normalize_mode($mode) if defined $mode;

    #So, technically, this makes the function’s name a misnomer since this
    #always attempts the mkdir() regardless of whether the node already
    #exists. The difference, though, is transparent to the user, and,
    #more importantly, we avoid TOCTTOU errors.
    #
    #We also want to avoid calling mkdir() directly so as not to produce an
    #exception--even one that we’ll just throw away--as this creates a
    #substantial overhead in loops.
    #
    my $return = _mkdir_list( $dir, $mode ) or do {
        _die_for_mkdir( $dir, $mode ) if $! != _EEXIST();
    };

    return $return ? 1 : 0;
}

sub _mkdir_list ( $dir, $mode ) {
    $dir = $dir // $_;
    _die_for_mkdir( '', $mode ) if not length $dir;

    return CORE::mkdir( $dir, $mode ) if defined $mode;

    return CORE::mkdir($dir);
}

sub _mkpath_list ( $dir, $mode = undef ) {
    $dir = $dir // $_;
    _die_for_mkdir( '', $mode ) if not length $dir;

    my $errors;

    if ( defined $mode ) {
        File::Path::make_path( $dir, { mode => $mode, error => \$errors } );
    }
    else {
        File::Path::make_path( $dir, { error => \$errors } );
    }

    return scalar @$errors;
}

sub _die_for_mkdir ( $dir, $mode ) {
    my $err = $!;

    local $@;
    require Cpanel::Exception;

    die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ error => $err, path => $dir, mask => $mode ] ) if defined $mode;
    die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ error => $err, path => $dir ] );
}

sub _normalize_mode ($mode) {

    # If a permission/mode number does not contain a leading 0 (i.e., 1777), it will not be handled as an octal number.
    # As such, we will convert any mode without a leading 0 to an octal number.
    $mode = oct($mode) if $mode =~ /^[1-7][0-7]{3}$/;

    Cpanel::Validate::OctalPermissions::is_octal_permission_or_die($mode);

    return $mode;
}

1;
