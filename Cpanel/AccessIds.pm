package Cpanel::AccessIds;

# cpanel - Cpanel/AccessIds.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::ForkSync             ();
use Cpanel::PwCache              ();
use Cpanel::Debug                ();
use Cpanel::LoadModule           ();
use Cpanel::AccessIds::SetUids   ();
use Cpanel::AccessIds::Normalize ();
use Cpanel::Sys::Setsid::Fast    ();

our $VERSION = '1.4';

=head1 NAME

Cpanel::AccessIds

=head1 DESCRIPTION

This module contains functions for performing an operation as another user.

=head1 COMPARISON TO OTHER MODULES

Two of the more commonly used functions for running as an unprivileged user are
do_as_user (from this_module) and call_as_user (from another module). The basic
differences between the two are:

=head2 Cpanel::AccessIds::do_as_user (from this module)

1. Runs the code in a child process.

2. Fully drops privileges.

3. Communicates the result back via piped Storable data.

=head2 Cpanel::AccessIds::ReducedPrivileges::call_as_user (a different module)

1. Runs the code in the same process.

2. Only partially drops privileges, so they can be restored when finished.

3. No need to serialize the response, so operates more simply.

=cut

=head1 FUNCTIONS

=cut

{
    no warnings 'once';
    *setuid            = *Cpanel::AccessIds::SetUids::setuids;
    *setuids           = *Cpanel::AccessIds::SetUids::setuids;
    *run_as_user_group = *runasusergroup;
    *run_as_user       = *runasuser;

=head2 do_as_current_user()

Perform an operation in a child process without dropping privileges.

This is implemented as an alias for Cpanel::ForkSync::do_in_child().

=cut

    *do_as_current_user = *Cpanel::ForkSync::do_in_child;
}

=head2 runasuser() / run_as_user()

Execute a shell command as the specified user in a child process.

No effort is made to communicate information back to the parent about the
child's output or exit status.

=cut

sub runasuser {
    my $user = shift;
    my $gid  = ( Cpanel::PwCache::getpwnam_noshadow($user) )[3];    # gets passed to setuids() which works w/ numeric id or name
    my @CMDS = @_;
    return runasusergroup( $user, $gid, @CMDS );
}

=head2 runasusergroup() / run_as_user_group()

Same as runasuser(), but allows you to specify a group instead of using whichever group
the user belongs to.

=cut

sub runasusergroup {
    my ( $user, $group, @CMDS ) = @_;
    my $homedir = '';
    if ( $user !~ m/^\d+$/ ) {
        $homedir = Cpanel::PwCache::gethomedir($user);
    }
    else {
        $homedir = Cpanel::PwCache::gethomedir($user);
    }

    if ( my $pid = fork() ) {
        waitpid( $pid, 0 );
    }
    elsif ( defined $pid ) {
        Cpanel::Sys::Setsid::Fast::fast_setsid();
        Cpanel::AccessIds::SetUids::setuids( $user, $group );
        $ENV{'HOME'} = $homedir;

        #
        #print "$>: running " . join( ' ', @CMDS ) . "\n";
        exec @CMDS or die "exec(@CMDS) failed: $!";
    }
    else {
        die "The system failed to fork because of an error: $!";
    }

    return;
}

=head2 do_as_user()

Execute a piece of code as another user in a child process. The return value, if any, will
be communicated back to the parent and returned. Exceptions will be silently discarded.

=cut

sub do_as_user {
    my ( $user, $code ) = @_;

    # gets passed to setuids() which works w/ numeric id or name
    return do_as_user_group( $user, undef, $code );
}

=head2 do_as_user_with_exception()

Roughly the same as do_as_user, but instead of discarding exceptions communicated
back from the child, re-throws them in the parent.
Note that this function calls fork(), so you might consider using a non-forking replacement
Cpanel::AccessIds::ReducedPrivileges::call_as_user() instead.

=head3 Cautionary note about security:

Use of do_as_user_with_exception() should be made with the understanding that the child
process is running as an untrusted user, and the parent needs to be OK with any exception,
including potentially bogus ones, that might be thrown. This is the same caution you
should also take when handling the return values from similar functions like do_as_user(),
just applied to exceptions.

The good news is that, because the exceptions pass through Storable, and we don't allow
reblessing in our Storable, they will not include any exception objects, only strings or
data structures.

=head3 Arguments:

  [0]: The username as which to run the thing
  [1]: Code ref for the thing to run

=head3 Returns:

If all goes well, the return value(s) of the code ref will be returned.

=head3 Throws:

If the code ref throws an exception in the child, the exception will be communicated
back to the parent and re-thrown. This means that callers of do_as_user_with_exception
may wrap it in an eval or try/catch in order to catch an exception from the child.

=cut

# Consider using Cpanel::AccessIds::ReducedPrivileges::call_as_user() instead to avoid fork()
sub do_as_user_with_exception {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my ( $code, $user, $group ) = Cpanel::AccessIds::Normalize::normalize_code_user_groups(@_);

    my $setuid_coderef = sub {
        Cpanel::Sys::Setsid::Fast::fast_setsid();
        Cpanel::AccessIds::SetUids::setuids( $user, $group );
        return $code->(@_);
    };

    my $forksync = Cpanel::ForkSync->new_quiet($setuid_coderef);

    if ( my $deserialize_err = $forksync->retrieve_error() ) {
        die "Failed to deserialize result from child: $deserialize_err";
    }
    elsif ( ref $forksync->structured_exception ) {
        die $forksync->structured_exception;
    }
    elsif ( $forksync->exception ) {
        die $forksync->exception;
    }

    my $ret = $forksync->return;
    if ( 'ARRAY' eq ref $ret ) {
        if (wantarray) {
            return @$ret;
        }
        else {
            # In scalar context, return the last element of the array, not the count.
            # This mimics the normal expected perl behavior had we not been using an array
            # and is needed in order for do_as_user_with_exception to match the scalar
            # context behavior of do_as_user.
            return $ret->[-1];
        }
    }

    return;    # Hopefully will never be reached
}

=head2 do_as_user_group()

Execute a piece of code in a child process as the specified user and group.

As with do_as_user(), the response, if any, will be communicated back from
the child to the parent and returned to the caller.

=cut

#NOTE: This returns either an array in list context
# a scalar (or last element in an array) in scalar context or undef.
# As of version 1.3, a scalar can now be correctly passed
# back.
# So this: my $foo = do_as_user_group( $user, $group, sub { return 'happy' } )
#...will actually set $foo to 'happy'
#
sub do_as_user_group {    ## no critic qw(Subroutines::RequireArgUnpacking)
    local $@;

    my ( $code, $user, $group ) = eval { Cpanel::AccessIds::Normalize::normalize_code_user_groups(@_) };

    #One of these will catch a failure from the eval{} above.
    #Ordinarily, that eval{} shouldn't be there, which would
    #allow the exception to propagate, but legacy code doesn't
    #expect that, so just fail "silently". There are worse things.
    return if !length $user;
    return if !length $group;

    if ( !$user || !$group ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        die Cpanel::Carp::safe_longmess("do_as_user_group may not be called for root.");
    }

    if ( !$code || ref $code ne 'CODE' ) {
        Cpanel::Debug::log_warn("Failed to provide CODE");
        return;
    }

    my $setuid_coderef = sub {
        Cpanel::Sys::Setsid::Fast::fast_setsid();
        Cpanel::AccessIds::SetUids::setuids( $user, $group );
        return $code->(@_);
    };

    return Cpanel::ForkSync::do_in_child($setuid_coderef);
}

1;
