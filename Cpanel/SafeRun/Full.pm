package Cpanel::SafeRun::Full;

# cpanel - Cpanel/SafeRun/Full.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#XXX
#This module is DEPRECATED. Use Cpanel::SafeRun::Object instead.
#----------------------------------------------------------------------

use strict;

use Cpanel::Chdir           ();
use Cpanel::SafeRun::Object ();
use Cpanel::Env             ();
use Cpanel::PwCache         ();

#----------------------------------------------------------------------
#XXX
#This module is DEPRECATED. Use Cpanel::SafeRun::Object instead.
#----------------------------------------------------------------------

sub _get_default_output_hash {
    my %output = ( 'status' => 0, 'message' => '', 'stdout' => '', 'stderr' => '', );
    return wantarray ? %output : \%output;
}

# Allows the caller to specify ENV keys to not cleanse prior to exec'ing the
# program in run(). run() will forcefully populate the keys in @keepers list,
# so this sub should be called immediately follow that variable assignment;
# it's this sub's responsibility to add items in the @keepers list to the 'keep'
# array that is passed to clean_env()
sub _prepare_env {
    my ( $parent_env, $env_hr ) = @_;
    return if ref $parent_env ne 'HASH';

    # ENV keys that run() cares about (and will already have put in local %ENV)
    my %keepers = ( 'HOME', undef, 'USER', undef, 'TMP', undef, 'TEMP', undef );

    # Make a 'keep' list in the hash ref that we're going to pass to clean_env if
    # the caller didn't provide it
    if ( ref $env_hr ne 'HASH' || !$env_hr->{'keep'} || ref $env_hr->{'keep'} ne 'ARRAY' ) {
        $env_hr->{'keep'} = [];
    }

    # If the 'keep' list and it's populated, copy the requested global %ENV
    # key/value pairs into local %ENV
    foreach my $extra_keep ( @{ $env_hr->{'keep'} } ) {

        # only populate local %ENV if both:
        #  - key is not already in the special list %keepers (which run() cares about)
        #  - key was actually set in global %ENV
        if ( !exists $keepers{$extra_keep} && exists $parent_env->{$extra_keep} ) {
            $ENV{$extra_keep} = $parent_env->{$extra_keep};
        }
    }

    # Add the special list %keepers to the 'keep' list that clean_env will receive
    push @{ $env_hr->{'keep'} }, keys %keepers;

    # finally
    Cpanel::Env::clean_env( %{$env_hr} );
}

# run
#
# chdir
#       Change directory to the supplied diirectory. Defaults to not changing directory.
# program
#       Full name of the program to execute. (Required)
# args
#       Reference to an array of arguments for the command. (Optional)
# stdin
#       Optional string or string-ref to send to the program on stdin. If not exist, stdin is connected to /dev/null
# timeout
#       The number of seconds to wait after a process stops responding (writing to stdout, or stderr)
#    to terminate it
# clean_env
#       Optional hash ref that will eventually be passed to Cpanel::Env::clean_env()
#       NOTE: HOME, USER, TMP, TEMP will be explicitly given value by run()
#       prior to the cleansing (and will be retained during cleansing via
#       _prepare_env())
#
#NOTE: This function's "status" return flag does NOT reflect the call's exit status.
sub run {
    my %OPTS   = @_;
    my $output = _get_default_output_hash();

    if ($Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED) {    # PPI NO PARSE --  can't be reduced if the module isn't loaded
        die __PACKAGE__ . " cannot be used with ReducedPrivileges. Use Cpanel::SafeRun::Object instead";
    }

    my ( $user, $homedir ) = ( Cpanel::PwCache::getpwuid_noshadow($>) )[ 0, 7 ];
    if ( !$homedir ) {
        $output->{'message'} = 'Invalid user';
        return $output;
    }
    my %parent_env = %ENV;
    local %ENV;
    $ENV{'HOME'} = $homedir;
    $ENV{'USER'} = $user;
    $ENV{'TMP'}  = $ENV{'TEMP'} = $homedir . '/tmp';
    _prepare_env( \%parent_env, $OPTS{'cleanenv'} );

    my $chdir;
    if ( $OPTS{'chdir'} ) {
        $chdir = Cpanel::Chdir->new( $OPTS{'chdir'} );
    }

    if ( $OPTS{'program'} ) {
        if ( !-e $OPTS{'program'} ) {
            $output->{'message'} = qq<program "$OPTS{'program'}" does not exist>;
            return $output;
        }
        if ( !-x $OPTS{'program'} ) {
            $output->{'message'} = qq<program "$OPTS{'program'}" is not executable>;
            return $output;
        }
    }
    else {
        $output->{'message'} = 'program not specified';
        return $output;
    }

    if ( $OPTS{'args'} ) {
        if ( ref $OPTS{'args'} ne 'ARRAY' ) {
            $output->{'message'} = 'program arguments invalid';
            return $output;
        }
    }
    else {
        $OPTS{'args'} = [];
    }

    my $run;
    {
        local $SIG{'PIPE'} = 'IGNORE' if length $OPTS{'stdin'};
        $run = Cpanel::SafeRun::Object->new(
            'program'  => $OPTS{'program'},
            'args'     => $OPTS{'args'},
            'keep_env' => 1,                  # handled above
            ( length $OPTS{'stdin'} ? ( 'stdin'        => $OPTS{'stdin'} )   : () ),
            ( $OPTS{'timeout'}      ? ( 'timeout'      => $OPTS{'timeout'} ) : () ),
            ( $OPTS{'timeout'}      ? ( 'read_timeout' => $OPTS{'timeout'} ) : () ),
        );
    }

    $? = $run->CHILD_ERROR();    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
    _augment_with_process_status($output);
    $output->{'timeout'} = $run->timed_out();
    $output->{'stderr'}  = $run->stderr();
    $output->{'stdout'}  = $run->stdout();
    $output->{'status'}  = 1;
    $output->{'message'} = 'Executed ' . $OPTS{'program'} . ' ' . join( ' ', @{ $OPTS{'args'} } );
    return $output;
}

sub _augment_with_process_status {
    my ($output) = @_;

    #Courtesy to the caller.
    @{$output}{ 'exit_value', 'did_dump_core', 'died_from_signal' } = (
        $? >> 8,
        $? & 0x80,
        $? & 0x7f,
    );

    return $output;
}

1;
