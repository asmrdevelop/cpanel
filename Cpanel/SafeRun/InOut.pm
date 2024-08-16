package Cpanel::SafeRun::InOut;

# cpanel - Cpanel/SafeRun/InOut.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#----------------------------------------------------------------------
#NOTE: This code does NOT accommodate the following:
#
#perl -e'eval { fork or die }; print 9'
#   This actually prints "99" because the die() in the child gets caught
#   by the eval {} rather than killing the process.
#----------------------------------------------------------------------

use Symbol ();

# lightweight open2 -- that requires no waitpid (done on close automatically with perl internals)
# NOTE: Are you sure that you don't want inout_with_default_signal_handlers() instead??
#
#Positional arguments:
#   0   - writer
#   1   - reader
#   2   - optional, coderef to execute before exec()
#   3.. - arguments to exec()
#
sub inout {
    my $wtr = $_[0] ||= Symbol::gensym();
    my $rdr = $_[1] ||= Symbol::gensym();

    my $child_read;

    if ($Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED) {    # PPI NO PARSE --  can't be reduced if the module isn't loaded
        die __PACKAGE__ . " cannot be used with ReducedPrivileges. Use Cpanel::SafeRun::Object instead";
    }

    pipe( $child_read, $wtr ) or warn "Failed to pipe(): $!";

    select( ( select($wtr),        $| = 1 )[0] );                  #aka $wtr->autoflush(1);
    select( ( select($child_read), $| = 1 )[0] );                  #aka $child_read->autoflush(1);

    if ( my $pid = open( $rdr, '-|' ) ) {
        close $child_read or warn $!;

        return $pid;
    }
    elsif ( defined $pid ) {
        close $wtr or warn $!;

        open( STDIN, '<&=' . fileno($child_read) );
        if ( ref $_[2] eq 'CODE' ) {
            $_[2]->();
            _exec( @_[ 3 .. $#_ ] );
        }
        else {
            _exec( @_[ 2 .. $#_ ] );
        }
        exit( $! || 127 );
    }
    else {
        return;
    }
}

#This avoids the following problem:
#
#perl -e'$SIG{USR1} = "IGNORE"; my $pid = fork or do { exec q<perl -e "kill q[USR1], $$"> }; waitpid $pid, 0; print $?'
#
#Here, exec() will preserve the parent's SIGUSR1 handler, so this actually
#prints "0", not "10" as you might expect.
#
sub inout_with_default_signal_handlers {

    #If we don't do this, then the exec()ed process will start off
    #ignoring whatever signals that $$ is IGNOREing.
    local @SIG{ keys %SIG } = ('DEFAULT') x keys %SIG;

    return inout(@_);
}

#
# Provide a mockable interface to allow callers to replace the exec with their intercepted call.
#
# Args:
#   Same as to exec.
sub _exec {
    exec(@_);
}

1;
