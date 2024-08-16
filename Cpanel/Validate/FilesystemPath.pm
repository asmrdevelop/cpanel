package Cpanel::Validate::FilesystemPath;

# cpanel - Cpanel/Validate/FilesystemPath.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::Exception                    ();
use Cpanel::Validate::FilesystemNodeName ();

#This throws no exception but also returns no error message.
sub is_valid {
    my ($node) = @_;

    my $err;
    try { validate_or_die($node) } catch { $err = $_ };

    return !$err ? 1 : 0;
}

sub die_if_any_relative_nodes {
    my ($path) = @_;

    validate_or_die($path);

    # regex to match relative paths
    if ( grep { $_ eq '.' || $_ eq '..' } split m</>, $path ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Relative filesystem nodes are invalid.' );
    }

    return 1;
}

#----------------------------------------------------------------------
# NOTE: This considers "../.." to be valid, but not "/../..".
# If you need to prevent back-traversal, look at die_if_any_relative_nodes(),
# or prefix '/' onto your $path.
#----------------------------------------------------------------------
#
sub validate_or_die {
    my ($path) = @_;

    if ( !length $path ) {
        die Cpanel::Exception::create('Empty');
    }

    my $original_name = $path;

    #Allow double-slashes since the OS doesn't care.
    $path =~ tr</><>s;

    #Leading/trailing slashes don't matter to validity,
    #but we need to know if this was an absolute path or not.
    my $is_absolute_path = index( $path, '/' ) == 0;
    substr( $path, 0, 1, '' ) if $is_absolute_path;
    chop($path)               if substr( $path, -1 ) eq '/';

    my $depth = 0;
    for my $piece ( split m</>, $path ) {
        next if $piece eq '.';

        if ( $piece eq '..' ) {
            if ($is_absolute_path) {
                $depth--;
                if ( $depth < 0 ) {
                    die Cpanel::Exception::create( 'InvalidParameter', 'This absolute path references a nonexistent parent directory.' );
                }
            }
            next;
        }

        $depth++ if $is_absolute_path;

        try {
            Cpanel::Validate::FilesystemNodeName::validate_or_die($piece);
        }
        catch {
            if ( UNIVERSAL::isa( $_, 'Cpanel::Exception::TooManyBytes' ) ) {
                die Cpanel::Exception::create( 'InvalidParameter', 'The node “[_1]” is too long: [_2]', [ $_->get('value'), $_->to_string_no_id() ] );
            }

            die $_;
        };
    }

    return 1;
}

1;
