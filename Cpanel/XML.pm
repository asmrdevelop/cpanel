package Cpanel::XML;

# cpanel - Cpanel/XML.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
##no critic qw(RequireUseWarnings)

use Cpanel::LoadModule           ();
use Cpanel::FastSpawn::InOut     ();
use Cpanel::AdminBin::Serializer ();
use Cpanel::ConfigFiles          ();
use Cpanel::LoadFile::ReadFast   ();

#Returns four values:
#   0) byte length of response
#   1) scalar ref to response   (\undef if fork/exec failed)
#   2) # of errors
#   3) errors as string (LF-separated)
#
sub cpanel_exec_fast {
    my ( $form_ref, $opts ) = @_;
    my $cpanel_bin = get_cpanel_bin( $opts->{'uapi'} ? 'uapi' : undef );
    my ( $readxml, $sendxml );

    my @args;
    if ( $opts->{'uapi'} ) {
        ## ./uapi.pl --json-connect --webmail (note: two dashes for 'webmail')
        @args = (
            ( $opts->{'json'}    ? '--json-connect' : '--xml-connect' ),
            ( $opts->{'webmail'} ? '--webmail'      : () )
        );
    }
    else {
        ## e.g. ./cpanel.pl --json-fast-connect --stdin -webmail (note: one dash for 'webmail')
        @args = (
            ( $opts->{'json'} ? '--json-fast-connect' : '--xml-fast-connect' ),
            '--stdin', ( $opts->{'webmail'} ? '-webmail' : () )
        );
    }

    $ENV{'NYTPROF'} = 'addpid=1:start=init:file=/tmp/nytprof.out' if $opts->{'nytprof'};    ##no critic qw(RequireLocalizedPunctuationVars)

    my $pid;

    local $SIG{'HUP'} = 'IGNORE';

    # this is not race condition free: view case 95037
    #   but the extra -x limit the problem to most of the case
    #   a solution close to what is done in the unit test should be applied
    if (
        -x $cpanel_bin && (
            $pid = Cpanel::FastSpawn::InOut::inout(
                $sendxml, $readxml,
                ( $opts->{'nytprof'} ? ( '/usr/local/cpanel/3rdparty/bin/perl', '-d:NYTProf' ) : () ),
                $cpanel_bin,
                @args
            )
        )
    ) {
        local ( $!, $@, $? );

        my @errs;
        eval { Cpanel::AdminBin::Serializer::DumpFile( $sendxml, {%$form_ref} ) } or do {
            my $err = $@ || $!;
            push @errs, "Failed to write to “$cpanel_bin”: $err";
        };

        close($sendxml) or warn "Failed to close send filehandle for “$cpanel_bin”: $!";

        local $/ = undef;
        $! = undef;

        # Avoid readline here as it sets $! when it gets interrupted
        # by a signal even if it successfully restarts
        my $output = '';
        Cpanel::LoadFile::ReadFast::read_all_fast( $readxml, $output );
        if ($!) {
            my $total_bytes_read = length $output;
            push @errs, "Failed to read from “$cpanel_bin” after reading “$total_bytes_read” bytes: $!";
        }

        close($readxml) or warn "Failed to close read filehandle from “$cpanel_bin”: $!";

        waitpid( $pid, 0 );
        my $child_err = $?;

        if ( $child_err & 127 ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Config::Constants::Perl');

            push @errs, sprintf( "“$cpanel_bin” died from signal %d (%s).", $child_err & 127, $Cpanel::Config::Constants::Perl::SIGNAL_NAME{ $child_err & 127 } );
        }
        elsif ( $child_err >> 8 ) {
            my $err = $child_err >> 8;

            Cpanel::LoadModule::load_perl_module('Errno');
            my $hash     = Errno::TIEHASH();
            my %err_type = reverse %$hash;

            push @errs, sprintf( "“$cpanel_bin” exited with status %d (%s).", $err, $err_type{$err} || '' );
        }

        use bytes;
        return wantarray ? ( length($output), \$output, ( scalar @errs ), join( "\n", @errs ) ) : $output;
    }
    Cpanel::LoadModule::load_perl_module('Cpanel::Logger');
    my $internal_error = "Failed to execute " . get_cpanel_bin() . ": $!";
    Cpanel::Logger->new()->warn($internal_error);
    my $output;
    return wantarray ? ( 0, \$output, 1, $internal_error ) : $output;
}

sub get_cpanel_bin {
    my ($app) = @_;
    $app ||= 'cpanel';
    return "$Cpanel::ConfigFiles::CPANEL_ROOT/$app";
}

1;
