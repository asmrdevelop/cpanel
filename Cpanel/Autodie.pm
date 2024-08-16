package Cpanel::Autodie;

# cpanel - Cpanel/Autodie.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Autodie - autodie.pm, à la cPanel

=head1 SYNOPSIS

    # The “open” and “link” functions will be compiled in.
    use Cpanel::Autodie qw( open link );

    # These die() on any failure.
    Cpanel::Autodie::open( my $rfh, '<', $path );
    Cpanel::Autodie::link( $old => $new );

    # This will lazy-load the “rmdir” function.
    Cpanel::Autodie::rmdir($path);

    # Explicitly load a function without using it:
    Cpanel::Autodie->import( 'close' );

=head1 DESCRIPTION

Use this module for error-checked I/O in Perl.

This confers many of autodie.pm's benefits without actually overwriting
Perl built-ins as that module does.

This module explicitly rejects certain "unsafe" practices that Perl built-ins
still support. Neither bareword file handles nor one-/two-arg C<open()>,
for example, are supported here--partly because it's more complicated to
implement, but also because those patterns are best avoided anyway.

This module also rejects use of a single Perl command to operate on multiple
files, as, e.g., C<chmod()> allows. This is because that is the only way to
have reliable error checking, which is the whole point of this module.

=head1 CAVEATS

=over

=item * Because we report errors here via exceptions, this module purposely
avoids setting globals C<$!> and C<$^E>.

=item * Functions added here should probably ONLY be named as the equivalent
Perl built-in. Deviate from that pattern with extreme care!

=item * Since this doesn't use function prototypes, some of the syntaxes
that Perl's built-ins support won't work here. A prominent example is:

    print { $wfh } 'Haha';

Instead, do:

    Cpanel::Autodie::print( $wfh, 'Haha' );

=item * Some functions are not implemented here by design:

=over

=item * C<readline()>: Perl's built-in does lots of "magic" that would be
hard to implement (e.g., considering '0' as true in a while()).

=item * C<readdir()>: Similar to why readline() is unimplemented.

=item * C<chdir()>: A process's directory is an OS-level “global variable”.
Anything that does change it should probably put it back. L<Cpanel::Chdir>
provides an easier solution for this, as do some CPAN modules.

=item * C<select()> with zero or one args. L<Perl::Critic> says not to use
it anyway.

=item * C<fork()>: Use Cpanel::ForkAsync instead.

=item * C<exec()>, C<system()>, and C<readpipe()>: Use
L<Cpanel::SafeRun::Object> instead.

=item * C<tell()>: This doesn’t seem to write to C<$!> and so can’t be
error-checked.

=item * C<pipe()>: We used to implement Cpanel::Autodie::pipe.
But it didn’t make a lot of sense since the only way C<pipe()> fails—assuming
Perl itself doesn’t mishandle it—is if the process has hit  its limit
on file descriptors, which complicates using the L<Cpanel::Exception>
module to report the error, the localization of the error message, and even the load
of the C<pipe()> function itself. Basically, this framework assumes
that it’s possible to create “a few” file descriptors to do its work;
given that C<pipe()> only fails when that assumption fails, it’s
not useful to use Cpanel::Autodie for it.

=back

Others are unimplemented because we simply don’t use them very often.
For example: C<write()>, C<binmode()>, C<ioctl()>, C<syscall()>,
shared memory stuff, etc.

=back

=head1 ADDING NEW FUNCTIONS

Functions that are added to this namespace should:

=over

=item * Execute a B<SINGLE> system call. This is the only reliable way
to indicate each and every failure.

=item * Implement all functionality of the corresponding Perl built-in,
even if all syntaxes are not supported.
For example, the C<open()> implementation here doesn’t support the 2-argument
syntax, but no application should need that syntax anyway to achieve the
intended functionality of C<open()>.

=item * Notwithstanding the above, functions in this namespace should
match the corresponding Perl built-in’s input/output signature as closely
as possible.

=item * Not overwrite any globals except when necessary and documented.

=item * Throw instances of L<Cpanel::Exception> subclasses, unless the
error is targeted purely at developers (e.g., wrong # of arguments).

=item * Throw on all errors unless explicitly named to accommodate
an error type. For example, C<unlink_if_exists()> tolerates C<ENOENT>.

=item * In the case of error-tolerant calls, indicate via return value
whether an error was tolerated. For example, C<shutdown_if_connected()>
returns falsy if the given socket wasn’t connected.

=item * All error conditions must be distinguishable. For instance, don’t
write a function C<rmdir_if_exists_and_not_empty()> (tolerant of
ENOENT and ENOTEMPTY) unless there is some clean way of distinguishing
success, ENOENT, ENOTEMPTY, and all other failures from each other.

=back

=cut

#----------------------------------------------------------------------

# Used freqeuntly in several “wrapper” functions.
# NB: Avoid constant.pm here because of weird memory issue in “-dormant”
# binaries.
sub _ENOENT { return 2; }
sub _EEXIST { return 17; }
sub _EINTR  { return 4; }

sub import {
    shift;

    _load_function($_) for @_;

    return;
}

our $AUTOLOAD;

sub AUTOLOAD {
    substr( $AUTOLOAD, 0, 1 + rindex( $AUTOLOAD, ':' ) ) = q<>;

    _load_function($AUTOLOAD);

    goto &{ Cpanel::Autodie->can($AUTOLOAD) };
}

sub _load_function {
    _require("Cpanel/Autodie/CORE/$_[0].pm");

    return;
}

# for tests
sub _require {
    local ( $!, $^E, $@ );

    require $_[0];
    return;
}

1;
