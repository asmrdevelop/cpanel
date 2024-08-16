package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/chmod.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# Can’t use signatures here because of perlpkg.
#

=encoding utf-8

=head1 FUNCTIONS

=head2 chmod( $MODE, $PATH_OR_FH )

cf. L<perlfunc/chmod>

NOTE: This will only chmod() one thing at a time. It refuses to support
multiple chmod() operations within the same call. This is in order to provide
reliable error reporting.

Note that, while

    Cpanel::Autodie::chmod(0755, $path1, $path2)

… is forbidden, you can still do:

    Cpanel::Autodie::chmod(0755, $_) for ($path1, $path2);

=cut

our $_TOLERATE_ENOENT;

sub chmod {
    my ( $mode, $target, @too_many_args ) = @_;

    #This is here because it's impossible to do reliable error-checking when
    #you operate on >1 filesystem node at once.
    die "Only one path at a time!" if @too_many_args;

    #NOTE: This breaks chmod's error reporting when a file handle is passed in.
    #cf. https://rt.perl.org/Ticket/Display.html?id=122703
    local ( $!, $^E );

    return CORE::chmod( $mode, $target ) || do {
        if ( $_TOLERATE_ENOENT && ( $! == _ENOENT() ) ) {
            undef;
        }
        else {
            my $err = $!;

            local $@;

            require Cpanel::Exception;

            require Cpanel::FileUtils::Attr;
            my $attributes = Cpanel::FileUtils::Attr::get_file_or_fh_attributes($target);

            require Cpanel::FHUtils::Tiny;
            if ( Cpanel::FHUtils::Tiny::is_a($target) ) {
                die Cpanel::Exception::create( 'IO::ChmodError', [ error => $err, permissions => $mode, immutable => $attributes->{'IMMUTABLE'}, 'append_only' => $attributes->{'APPEND_ONLY'} ] );
            }

            die Cpanel::Exception::create( 'IO::ChmodError', [ error => $err, permissions => $mode, path => $target, immutable => $attributes->{'IMMUTABLE'}, 'append_only' => $attributes->{'APPEND_ONLY'} ] );
        }
    };
}

#----------------------------------------------------------------------

=head2 chmod_if_exists( $MODE, $PATH_OR_FH )

Like C<chmod()> but returns undef on ENOENT.

=cut

sub chmod_if_exists {
    my ( $mode, $target, @too_many ) = @_;

    local $_TOLERATE_ENOENT = 1;

    return &chmod( $mode, $target, @too_many );    ## no critic qw(Ampersand)
}

1;
