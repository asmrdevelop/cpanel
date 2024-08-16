package Cpanel::Usage;

# cpanel - Cpanel/Usage.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#

#----------------------------------------------------------------------
# XXX: Do not use this module. - JNK
#----------------------------------------------------------------------

### The 'strict' and 'warnings' pragmas are essential during devel, but must be
### turned off for production.
#use strict;
#use warnings;

# Using a global for the preferences is much more practical in
# this case than trying to pass the additional prepended hash
# ref, if present, from wrap_options() to getoptions(). We'd
# have to test for the presence of the additional arg in both of
# those subroutines, which is already cumbersome even to do just
# once. This obviates the need for that.

my $g_prefs;    # Ref to hash containing up to three boolean preferences, as follows:

#
# strict           If true, every --xxx switch found on the command line must
#                  have a corresponding entry in the opts hash passed in.
#
# remove           If true, all --xxx switches (and their following arg, if any)
#                  will be removed from the command line after processing.
#
# require_left     If true, all --xxx switches (and their following arg, if any)
#                  must appear leftmost on the command line, before any
#                  non-option args.
#
# default_value    All undefined --xxx switches will have a the value assigned
#                  here.

$Cpanel::Usage::VERSION = '1.08';

sub version {    # Reports our current revision number.
    $Cpanel::Usage::VERSION;
}

# Subroutine wrap_options() is the primary entry point into this
# module. Call it to get both of the two main units of
# functionality provided by this module:
#
# (1) When '--help' (or one of its synonyms) is detected on the
# command line, invoke a specified (i.e., if specified) usage
# subroutine;
#
#  -- OTHERWISE --
#
# (2) process --xxx switches from the command line.

sub wrap_options {
    my $arg1 = $_[0];
    $g_prefs = {};
    if ( defined $arg1 && ( ref $arg1 ) =~ /\bHASH\b/ ) {    # hash of preferences
        $g_prefs = $arg1;
        shift;
    }
    my ( $ar_argv, $cr_usage, $hr_opts ) = @_;
    getoptions( usage( $ar_argv, $cr_usage ), $hr_opts );
}

#
# Subroutine usage() implements the simpler of the two main
# units of functionality provided by this module. Namely, when
# '--help' or '-h' or '--usage' is detected on the command line,
# it invokes code (if specified as a code ref argument to this
# function) that will --presumably-- emit correct and complete
# usage info; the routine should also probably exit.
#
# If no usage code ref is passed in, we return 1, and let the
# caller deal with running usage comments.
#

sub usage {
    my ( $ar_argv, $cr_usage ) = @_;
    foreach my $arg (@$ar_argv) {
        if ( $arg =~ /^-+(h|help|usage)$/ ) {
            if ( defined($cr_usage) ) {
                &$cr_usage();
            }
            return 1;
        }
    }

    $ar_argv;
}

# The getoptions() subroutine implements the second of the two
# primary units of functionality provided by this module,
# namely, it processes switches of the form --xxx (or -xxx) found
# in the array whose ref is the first arg to this function, and
# assigns a value to each such switch (aka option argument)).
#
# If the switch is of the form --k=v, then v is taken as the
# argument value of switch --k.
#
# Otherwise:
#
# If the switch is a not a lone switch, that is, if it is
# followed by another arg which is itself not prefixed by a
# hyphen, that arg is taken as the argument value of the given
# switch.
#
# Otherwise (it is a lone switch):
#
# It will be assigned an implicit argument of boolean true (1).
#
# . . .
#
# The second arg to this function is a hash ref.
#
# If a ref to an empty hash is received, then each
# switch-and-value pair processed off the arg array (as
# described just above) is inserted into the given hash as
# switch => value. (This is known as "build as you go".)
#
# Otherwise (a non-empty hash was received):
#
# The members of the hash are all assumed to be of the form
#
#      'x' => \$x
#
# The value of the switch (as determined by the rules spelled
# out just above) is assigned accordingly to variable $x.
#
# NOTE: This function does not support multiple spellings of the
# same option as Getopt::Long does, e.g.: --help|?
sub getoptions {
    my ( $ar_cmdline, $hr ) = @_;

    my $non_opt_arg_seen = "";

    # If $ar_cmdline is not a ref to an array (of command line args),
    # then it is almost certainly scalar '1' as returned by
    # usage( ), which wrap options() then passes to this
    # getoptions() subroutine. No point proceeding further here;
    # in fact we cannot. That's how usage() was coded: to
    # alternately return a ref to an array of args, or '1'.
    # Dubious.

    return $ar_cmdline if ( ref $ar_cmdline || "" ) !~ /\bARRAY\b/;

    # If the first of two args to this function is 1, it is
    # (almost certainly) the result of our being called from
    # wrap_options(), which calls us with our first argument
    # being whatever is returned by a call to usage(), but
    # without a code reference (see comments to usage() function
    # herein). Function usage() should not be run this way
    # generally.

    if ( !$#$ar_cmdline && $ar_cmdline->[0] eq "1" ) {
        return 1;
    }

    # If our second argument is not a hash reference, we are
    # dead in the soup.

    unless ( defined $hr && ( ref $hr ) =~ /\bHASH\b/ ) {
        print "Error: opts must be a hash reference\n";
        return 2;
    }

    my $predefined = keys %{$hr};

    my @cmdline_out = @$ar_cmdline;    # save a copy of the arg array

    # Is it the rare no-switch case? That is, if we have
    # received a ref to an empty hash as our second arg, and the
    # arg array ref'ed by our first arg contains only non-opt
    # args and no --xxx switches, then we insert all those
    # non-opt args into the hash as hash values; the keys will be
    # integers ascending from zero. And we're done here.

    if ( !$predefined ) {
        if ( no_switches($ar_cmdline) ) {
            my $i = 0;
            foreach my $arg (@$ar_cmdline) {
                $hr->{ $i++ } = $arg;
            }
            return "";
        }
    }
    if ($predefined) {
        my $default_value = exists $g_prefs->{'default_value'} ? $g_prefs->{'default_value'} : 0;

        # this is the old 'foo' => \$var setup
        foreach my $k ( keys %$hr ) {

            # Convert undefined values to zeroes.
            #
            # Each value in the opts hash is usually just a
            # scalar (string). But not always. In the
            # multi-value option case, the value will itself be
            # a hash. Hence the following.

            if ( ref( $hr->{$k} ) =~ /^HASH/ ) {
                foreach my $kk ( keys %{ $hr->{$k} } ) {
                    ${ $hr->{$k}->{$kk} } = $default_value unless ( defined ${ $hr->{$k}->{$kk} } );
                }
            }
            else {
                ${ $hr->{$k} } = $default_value unless ( defined ${ $hr->{$k} } );
            }
        }
    }

    # Now loop thru the argument list, looking for --xxx switches, and
    # processing them as appropriate.
    my $seen_dash_dash = 0;

    for ( my $i = 0; $i <= $#$ar_cmdline; $i++ ) {
        if ( $ar_cmdline->[$i] eq '--' ) {
            $seen_dash_dash = 1;

        }
        elsif ( !$seen_dash_dash && $ar_cmdline->[$i] =~ /^-+(.+)$/ ) {
            my $o = $1;

            if ( "" ne $non_opt_arg_seen and $g_prefs->{'require_left'} ) {
                print qq{Error: Preference require_left was specified, all opt args must therefore appear first on the command line; option "-$o" found after "$non_opt_arg_seen" violates this rule\n};
                return 3;
            }
            my $eq_value = '';

            # "?" in following regex is for non-greedy match.
            # Thus, for "--x=y=z" we will take "x" as the
            # option name and "y=z" as the option value. But
            # greedy match would take "x=y" as the option
            # name, and "z" as the option value.

            if ( $o =~ /(.+?)=(.+)/ ) {
                $o        = $1;
                $eq_value = $2;
                $eq_value =~ s@^\s+@@;
                $eq_value =~ s@\s+$@@;
            }

            if ( $g_prefs->{'strict'} && $predefined && !exists $hr->{$o} ) {
                print qq{Error: While "strict" is in effect, we have encountered option --$o on the command line, an option that was not specified in the opts hash.\n};
                return 4;
            }

            # boolean or multilevel
            if (    # It is a "lone switch", that is, an
                    # option arg that either is the very last
                    # of all args, or is followed immediately
                    # by yet another --xxx switch. Either way,
                    # we cannot take the next arg as the value
                    # of the current option arg.
                $eq_value eq '' && ( $i == $#$ar_cmdline
                    || $ar_cmdline->[ $i + 1 ] =~ /^-+.+$/ )
            ) {

                # multilevel types can only be boolean
                if ( ref( $hr->{$o} ) =~ /^HASH/ ) {

                    # multilevel only for predefined
                    foreach my $kk ( keys %{ $hr->{$o} } ) {
                        if ($predefined) {
                            ${ $hr->{$o}->{$kk} }++ if ( exists( $hr->{$o} ) );
                        }
                    }
                }
                else {
                    if ($predefined) {
                        ${ $hr->{$o} }++ if ( exists( $hr->{$o} ) );
                    }
                    else {
                        $hr->{ _multihelp($o) }++;
                    }
                }
            }

            else {    # not a "lone switch"; the next arg might be the value
                      # to assign to the current option arg
                if ( ref( $hr->{$o} ) =~ /^HASH/ ) {
                    print "Error: A multi-level option can only be used when implicitly boolean (true), but you have attempted to use a multi-level option with an explicitly specified option argument.\n";

                    return 5;
                }
                if ( $eq_value ne '' ) {    # Sorry, we already have a value for the switch
                    if ($predefined) {
                        ${ $hr->{$o} } = $eq_value if ( exists( $hr->{$o} ) );
                    }
                    else {
                        $hr->{$o} = $eq_value;
                    }
                }
                else {                      # We have no value yet for the switch, so use next arg as the value
                    $cmdline_out[$i] = undef if $g_prefs->{'remove'};
                    ++$i;
                    if ($predefined) {
                        ${ $hr->{$o} } = $ar_cmdline->[$i]
                          if ( exists( $hr->{$o} ) );
                    }
                    else {
                        $hr->{$o} = $ar_cmdline->[$i];
                    }
                }
            }
            $cmdline_out[$i] = undef if $g_prefs->{'remove'};
        }
        else {    # It's a regular (non-hyphen-prefixed) arg, not an option arg
            if ( "" eq $non_opt_arg_seen ) {
                $non_opt_arg_seen = $ar_cmdline->[$i];
            }
        }
    }

    if ( $g_prefs->{'remove'} ) {

        # Caller requested that --xxx switches be removed from
        # the command line after processing. We have already
        # undefined them, now we just need to strip them out.

        @cmdline_out = grep { defined } @cmdline_out;
        @{$ar_cmdline} = @cmdline_out;
    }

    return "";    # aka 0, successful completion
}

# Map all synonyms of "--help" to "help". Note: The
# leading hyphens are already out of the picture.

sub _multihelp {    # For internal use only
    my $name = shift;
    return $name =~ /^(h|help|usage)$/ ? 'help' : $name;
}

# Subroutine no_switches() returns true if the argument array
# contains no hyphen-prefixed arguments, else it returns false.
sub no_switches {
    my $ar = shift;
    return !grep { /^-+.+/ } @{$ar};
}

# Subroutine dump_args() can be used to display the contents of
# the options hash; it is intended primarily as a debugging aid.

sub dump_args {
    my $hr_opts = shift;
    require Data::Dumper;
    print Data::Dumper::Dumper($hr_opts);
}

1;

__END__

=head1 NAME

Cpanel/Usage.pm - A command line argument parser and generic front-end for --help requests.

=head1 SYNOPSIS

  use Cpanel::Usage;

  $ar_args = Cpanel::Usage::usage(\@ARGV, \&usage);

  $ar_args = Cpanel::Usage::usage(\@ARGV);

  $err = Cpanel::Usage::getoptions(\@ARGV, \%options);

  $err = Cpanel::Usage::getoptions(\@someotherlist, \%options);

and even

  $err = Cpanel::Usage::getoptions(Cpanel::Usage::usage(\@ARGV, \&usage), \%options);

or put another way:

  $err = Cpanel::Usage::wrap_options(\@ARGV, \&usage, \%options);

Also, wrap_options() can now be invoked with preferences to
change some of its default behavior:

  $preferences = { strict => 1, remove => 1, require_left => 1 } ;
  $err = Cpanel::Usage::wrap_options($preferences, \@ARGV, \&usage, \%options);

And finally, for debugging:

  Cpanel::Usage::dump_args(\%opts);

=head1 DESCRIPTION

This module provides two basic related units of functionality, as well
as capability to use both of those jointly.

=over 4

=item *

usage() is a generalized facility for detecting and responding to
--help requests. When '--help' or one of its synonyms is found
on the command line, a user-defined usage subroutine is invoked,
if defined.

=item *

getoptions() parses and processes --xxx switches from the command line,
assigning a value, determined explicitly or implicitly, to each such
option (aka switch).

=item *

wrap_options() combines the functionality of C<usage()> and
C<getoptions()> into a single invocation (so named because it "wraps"
up the whole deal into one sweet bundle).

=back

The "help" requests to which usage() responds are -h, -help,
-usage, as well as their two-hyphen variants.

As suggested by the SYNOPSIS above, the argument array passed in
by reference is most typically C<@ARGV>, although the list could
be from anywhere. In all events, with one exception the argument
list is not trashed in any way. The exception is when the user
of this module explicitly requests such modification by
specifying the "remove" preference (for more on preferences, see
the note to version 1.07 later). Mainly for historical reasons,
removal of options from the command line is not the default
behavior of this module, although it is probably what most
developers have come to expect from command line processors,
generally.

Even under preference "remove", only the --xxx switches and
their explicit arguments, if any, are removed from the argument
list. The other remaining arguments will remain, and be treated
as input file names. If the application for some reason wishes
that stdin be read instead of those input files, it should
C<undef @ARGV>;

When calling usage() and wrap_options() the caller may pass a
reference to a local usage() routine; this module, upon
detecting a help request on the command line, will execute the
given function. Note, however, that the specified subroutine
should include an C<exit> (or C<die>) from the process, if that
is appropriate, which it usually is; thus, it should be
considered the normal scenario. In this case, control will never
return to this module's usage() function.

If, however, when a --help request is detected no code reference
is defined, or if it is indeed supplied, but the specified
subroutine does not terminate, and control does return to this
module's C<usage()> function, it will return with a value of 1.

Conversely, if C<usage()> detects no --help request (or any of
its synonyms), C<usage> returns the command line arguments
themselves, which the caller may then submit for further further
option parsing. This behavior is most useful internally to this
module, in the wrap_options() subroutine, which takes the
argument list it so receives back from usage(), and passes it on
to getoptions(). As noted earlier, wrap_options() is merely a
shorthand for piggybacking the functionality of those two
functions.

So much for the return values from C<usage()>.

Subroutines getoptions() and wrap_options() share the same
return values (because the latter calls the former, and
returns whatever it returned). The return values are as follows:

=over 4

=item 0 : Successful completion

=item 1 : The subroutine has received the scalar value 1 as its
first argument, instead of any array reference. The cause
is almost certainly that a --help request was detected on
the command line, but either the caller supplied an undefined
usage code reference, or the supplied subroutine was not
sufficiently inspired and well-behaved to die() or exit.

=item 2 : The opts hash passed in was undef, or not a reference,
or not a hash reference.

=item 3 : Preference C<require_left> was specified, but the args in the
argument array were found not to comply.

=item 4 : Preference C<strict> was specified, but the args in the
argument array were found not to comply.

=item 5 : A multi-value switch was found in the opts hash, and the
corresponding switch in the arg array has an associated explicit
value, whereas multi-value switches can take an implicit boolean
value only.

=back

It is important to realize that if one of the return codes 3, 4,
or 5 is returned, the caller's local scalar variables to which
she passed references in the options hash may now be in an
inconsistent state; that is, if any of them were changed before
the error was encountered. Therefore, when receiving one of
those error return codes, the calling application would do well
to reinitialize those local variables to undef before making a
subsequent call to wrap_options() or getoptions().

Option processing provided by this module is generally similar
to that of C<Getopt::Short> and C<Getopt::Long>, at least in the
sense that the scalar references (if any) passed in to the
options hash are used to set local scalar variables in the
calling program for any matching switches found on the command
line.

The scalar references need not be initialized prior to calling
wrap_options() or getoptions(), as this function provides for
setting anything uninitialized to zero.

Any command line argument which appears to have no
attendant value following it is treated as a boolean. More generally,
the algorithm used to determine a value for each --xxx switch
encountered is as follows:

=over 4

=item If the switch is of the form --k=v, then v is taken as the
argument value of switch --k.

Otherwise:

If the switch is a not a lone switch, that is, if it is
followed by another arg which is itself not prefixed by a
hyphen, then that arg is taken as the argument value of the given
switch.

Otherwise (it is a lone switch):

The switch will be assigned an implicit boolean value of 1 (true).

=back

If the value of any key-value pair passed to this module
in the options hash is itself a hash, it is understood to indicate
a multi-valued switch. This means, simply, that the value of
the given --xxx switch on the comand line will be used to set
I<multiple> local scalar values, rather than just one, as in
the normal case. Those multiple local scalar values appear as
the values of that subhash.

The argument list must be passed as a reference to a non-empty
array. The options must be passed as a reference to a (possibly
empty) hash.

A dump_args() function has been included in the module mainly
for testing purposes.

To determine this module's version information, call its
version() subroutine, which simply returns $VERSION from that
namespace. You can also query $Cpanel::Usage::VERSION directly.

As of version 1.04 we have included functionality to build the
options hash from the command line itself, if an empty opts hash
is received ("build as you go").

When a ref to a non-empty hash is passed, values will be
assigned to local scalars only for the keys present. Conversely,
the 'build as you go' form assigns keys from any switch, except
that '--h, --help, --usage' all get mapped down to 'help'.

With version 1.07 comes capability to alter the default behavior
of this module by prepending a hash ref of boolean preferences
to the arguments passed to wrap_options() (see SYNOPSIS). Those
preferences are:

=over 4

=item C<strict> : Enforces that no --xxx switch will be accepted from
the command line if it does not have a corresponding entry in
the options hash. Under this preference, the hash ref (if not
empty) should be seen as asserting not merely what to do when
particular options are encountered on the command line, but also
which options are valid in the first place. The default
behavior of this module is to accept any option arguments in the
arg array regardless of whether or not it is mentioned in the
options hash.

Note, though, that this C<strict> preference can
obviously be enforced only when a non-empty options hash is
received.

=item C<remove> : Arranges that each --xxx switch (and its
accompanying option argument, if any) will be removed from the
argument list after being processed. The default behavior of
this module is to leave the argument list unchanged.

=item C<require-left> : Enforces that all --xxx switches (and their
arguments, if any) must appear leftmost in the argument array,
before any non-option arguments appear (arguments not introduced
by a hyphen, and not being the argument to a hyphen-introduced
argument). The default behavior of this module is to allow
option arguments and non-option arguments to be intermingled
freely within the argument array.

=back

Note: We call them preferences instead of options, to
differentiate them as passed I<to> this Cpanel::Usage module to
control its behavior, that is, rather than being an option
specified to a command-line app that is processed I<by> the
module, in order to control the behavior of the app.

Note, too, that the preferences are accessible only via
wrap_options(), which in turn calls getoptions(), but they are
not accessible when you call getoptions() directly.

=head1 BUGS AND OTHER ISSUES

The curious can find a list of these in Fogbugz case 45620.
There just might be one or more others, too, not included there.

=head1 EXAMPLES

See /usr/local/cpanel/t/Cpanel-Usage.t

=cut
