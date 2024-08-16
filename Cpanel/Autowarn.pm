package Cpanel::Autowarn;

# cpanel - Cpanel/Autowarn.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Autowarn - Non-fatal I/O that warns on unexpected errors

=head1 SYNOPSIS

    use Cpanel::Autowarn         ();
    use Cpanel::Autowarn::unlink ();  # NOTE: Optional!

    if ( Cpanel::Autowarn::unlink($path) ) {
        print "unlinked “$path”!";
    }
    else {
        print "“$path” doesn’t exist!";
    }

=head1 READ THIS FIRST!

Use this module B<only> when there is B<no> failure condition that should
be considered a “show-stopper”. Examples:

=over

=item * Reading a cache file when the uncached version is available
as a fallback.

=item * Deleting a file that nothing will reference anymore.

=back

=head1 DESCRIPTION

Perl’s default I/O logic makes no distinction between “reasonably
expected” errors and “reasonably unexpected” ones. For instance,
C<unlink()> is often called in a context where the file may already
be deleted, in which case the resulting ENOENT failure is unremarkable.
If, however, that same system call reveals something more
“surprising”—say, EBUSY, ELOOP, etc.—then that’s probably
worth letting people know about.

“Classically”, the way to do this would be for the C<unlink()> to create
an exception, then the calling code would trap that exception and turn it
into a warning. In Perl, though, that’s wasteful, particularly in tight
loops. And while there are many contexts when an unexpected error should
cause an exception to propagate back through the call stack, in certain other
contexts we want I/O errors to give warnings only.

This module attempts to resolve these conflicting concerns.

=head1 INTERNALS

The original L<Cpanel::Autodie> implementation put all functions into the
same module, which made the module easy to call into but expensive to load.
There are now a number of submodules of L<Cpanel::Autodie> where the “real”
code lives, and it’s sometimes hard to recall which functions are where.

This module attempts to improve on that by putting all functions into the
same namespace but making the functions live in different modules. For
example, C<unlink()> lives in F<Cpanel/Autowarn/unlink.pm>, but that file’s
declared package is C<Cpanel::Autowarn>. Each function’s module is lazy-loaded
via an AUTOLOAD function. This only happens once per function, so it should be
safe in terms of performance; however, if desired, a caller can, e.g.,
C<use Cpanel::Autowarn qw(unlink)> to have the relevant function(s) loaded at
compile time.

=head1 HOW TO ADD TO THIS FRAMEWORK

=over

=item * Generally there will be one, maybe two error states that you want to
consider “expected”. For C<rmdir>, for example, that would be ENOENT.

=item * Strive for consistency with existing implementations.

=item * Trap C<$!> and C<$^E>. No harm comes in leaving global state alone,
but some buggy code will be vulnerable to changes this module would
otherwise make.

=item * Avoid ambiguous returns. Perl’s built-in C<unlink()>, for example,
accepts multiple filenames but internally calls C<unlink()> on them one
at a time. The return is just a count of nodes deleted, which doesn’t tell
us which nodes actually B<were> deleted. For this reason,
C<Cpanel::Autowarn::unlink()> forbids multiple-node input to its C<unlink()>.

=item * Notwithstanding the previous point, make your function as much of a
drop-in replacement for Perl’s built-ins as possible.

=back

=cut

#----------------------------------------------------------------------

use constant {
    _ENOENT => 2,
};

sub import {
    shift;

    _load_function($_) for @_;

    return;
}

our $AUTOLOAD;

sub AUTOLOAD {
    substr( $AUTOLOAD, 0, 1 + rindex( $AUTOLOAD, ':' ) ) = q<>;

    _load_function($AUTOLOAD);

    goto &{ Cpanel::Autowarn->can($AUTOLOAD) };
}

sub _load_function {
    _require("Cpanel/Autowarn/$_[0].pm");

    return;
}

# for tests
sub _require {
    local ( $!, $^E, $@ );

    require $_[0];
    return;
}

1;
