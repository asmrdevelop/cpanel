package Cpanel::SafeRun::Env;

# cpanel - Cpanel/SafeRun/Env.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic (RequireUseWarnings)

use Cpanel::Env   ();
use Cpanel::Debug ();

our $VERSION = '1.0';

sub saferun_r_cleanenv {
    return saferun_cleanenv2( { 'command' => \@_, 'return_ref' => 1, 'cleanenv' => { 'http_purge' => 1 } } );
}

sub saferun_cleanenv2 {
    my $args_hr = shift;
    return unless ( defined $args_hr->{'command'} && ref $args_hr->{'command'} eq 'ARRAY' );
    if ($Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED) {    # PPI NO PARSE --  can't be reduced if the module isn't loaded
        die __PACKAGE__ . " cannot be used with ReducedPrivileges. Use Cpanel::SafeRun::Object instead";
    }

    my @command                   = @{ $args_hr->{'command'} };
    my $return_reference          = $args_hr->{'return_ref'};
    my $error_output              = $args_hr->{'errors'};
    my %cleanenv_args             = defined $args_hr->{'cleanenv'} && ref $args_hr->{'cleanenv'} eq 'HASH' ? %{ $args_hr->{'cleanenv'} }             : ();
    my $check_cpanel_homedir_user = defined $args_hr->{'check_cpanel_homedir_user'}                        ? $args_hr->{'check_cpanel_homedir_user'} : 1;

    return if ( substr( $command[0], 0, 1 ) eq '/' && !-x $command[0] );
    my $output;
    if ( !@command ) {
        Cpanel::Debug::log_warn('Cannot execute a null program');
        return \$output if $return_reference;
        return $output;
    }
    require Cpanel::Env;
    local ( $/, *PROG, *RNULL );

    no strict 'refs';
    open( RNULL, '<', '/dev/null' );    ## no critic(InputOutput::ProhibitBarewordFileHandles InputOutput::RequireCheckedOpen)
    my $pid = open( PROG, "-|" );       ## no critic(InputOutput::ProhibitBarewordFileHandles)
    if ( $pid > 0 ) {
        $output = <PROG>;
    }
    elsif ( $pid == 0 ) {
        open( STDIN, '<&RNULL' );
        if ($error_output) {
            open STDERR, '>&STDOUT';
        }
        Cpanel::Env::clean_env(%cleanenv_args);
        if ( $check_cpanel_homedir_user && ( !$Cpanel::homedir || !$Cpanel::user ) ) {
            ( $ENV{'USER'}, $ENV{'HOME'} ) = ( getpwuid($>) )[ 0, 7 ];    #do not use PwCache here
        }
        exec(@command) or exit(1);                                        # Not reached
    }
    else {
        Cpanel::Debug::log_warn('Could not fork new process');
        return \$output if $return_reference;
        return $output;
    }
    close(PROG);
    close(RNULL);
    waitpid( $pid, 0 );
    return \$output if $return_reference;
    return $output;
}

1;
