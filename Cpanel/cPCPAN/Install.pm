package Cpanel::cPCPAN::Install;

# cpanel - Cpanel/cPCPAN/Install.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic(RequireUseWarnings) -- needs a comprehensive audit

use IPC::Open3 ();
use IO::Handle ();

our $INSTALL_TIMEOUT = 5000;

our $SANDBOX_PERL = '/usr/local/cpanel/scripts/cpan_sandbox/x86_64/perl';
our $CPANM_BIN    = '/usr/local/cpanel/bin/cpanm';

sub install {    ## no critic(ProhibitExcessComplexity)
    my ( $self, @MODS ) = @_;

    require Cpanel::cPCPAN;
    require Config;

    local $ENV{'FROM_PERLINSTALLER'} = 1;

    # by default this is going to use the system Perl
    my @CALL_CPANM = ($CPANM_BIN);
    my @CPANM_ARGS;
    my @OK_MODS;

    foreach my $mod (@MODS) {

        # Copied from Cpanel::StringFunc::is_namespace (but not loaded for memory savings)
        if ( is_namespace($mod) || $mod =~ m/^\-\-\w/ || ( $mod =~ m/^file:(?:\S+)/ && !$ENV{'WHM50'} ) ) {
            if ( $mod eq '--force' ) {
                push @CPANM_ARGS, '--reinstall';
                next;
            }
            if ( $mod =~ m/^file:/ && $mod !~ m{^file://} ) {
                my ($modfile) = $mod =~ /^file:(\S+)/;
                if ( $modfile !~ m{^/} && length $Cpanel::cPCPAN::startdir ) {
                    $modfile = $Cpanel::cPCPAN::startdir . '/' . $modfile;
                }
                ($modfile) = $modfile =~ /(.*)/;
                print "Reading module list from file $modfile\n";
                open my $mf_fh, '<', $modfile or die "Could not open $modfile for reading: $!";
                while (<$mf_fh>) {
                    chomp;
                    if ( is_namespace($_) ) {
                        push @OK_MODS, $_;
                    }
                }
                close $mf_fh;
            }
            else {
                push @OK_MODS, $mod;
            }
        }
        else {
            require Cpanel::Encoder::Tiny;
            my $xss_safe_mod = Cpanel::Encoder::Tiny::safe_html_encode_str($mod);
            print "Bad module name ($xss_safe_mod) detected, skipping it.\n";
        }
    }

    die "no valid modules given" if !@OK_MODS;

    push @CPANM_ARGS, @OK_MODS;

    eval {
        require IO::Tty;
        require Expect;
        $self->{'hasperlexpect'} = 1;
    };
    $self->{'expect_perl_load_err'} = $@;

    require Cpanel::CachedCommand;    # PPI USE OK -- makes Cpanel::Tar faster
    require Cpanel::Tar;
    my $tarcfg = Cpanel::Tar::load_tarcfg();

    local $ENV{'TAR_OPTIONS'};
    if ( $tarcfg->{'working_env'} ) {
        $ENV{'TAR_OPTIONS'} = $tarcfg->{'no_same_owner'} . ( $tarcfg->{'no_same_permissions'} ? ' ' . $tarcfg->{'no_same_permissions'} : '' );
    }
    else {
        delete $ENV{'TAR_OPTIONS'};    # tar 1.13.25 will segfault with TAR_OPTIONS env set
    }
    local $ENV{'GD_LIBS'}      = $ENV{'GD_LIBS'};
    local $ENV{'PATH'}         = $ENV{'PATH'};
    local $ENV{'BZLIB_LIB'}    = $ENV{'BZLIB_LIB'};
    local $ENV{'LDFLAGS'}      = $ENV{'LDFLAGS'};
    local $ENV{'OTHERLDFLAGS'} = $ENV{'OTHERLDFLAGS'};
    local $ENV{'EXTRALIBDIR'}  = $ENV{'EXTRALIBDIR'};
    if ( -e '/usr/lib64' ) {

        if ( -x $SANDBOX_PERL ) {

            # calling cpanm using --perl is deprecated and fragile
            @CALL_CPANM = ( $SANDBOX_PERL, '-S', $CPANM_BIN );
        }
        $ENV{'GD_LIBS'}      = '-L/usr/lib64 -L/usr/X11R6/lib64';
        $ENV{'PATH'}         = "/usr/local/cpanel/scripts/cpan_sandbox/x86_64:$ENV{'PATH'}";
        $ENV{'BZLIB_LIB'}    = '/usr/lib64';
        $ENV{'LDFLAGS'}      = '-L/usr/lib64 -L/usr/X11R6/lib64';
        $ENV{'OTHERLDFLAGS'} = '-L/usr/lib64 -L/usr/X11R6/lib64';
        $ENV{'EXTRALIBDIR'}  = '/usr/lib64';
    }

    require Cpanel::Sys::Compiler;
    print "Checking C compiler....";
    my ( $compiler_status, $compiler_messages, $preferred_flags ) = Cpanel::Sys::Compiler::check_c_compiler( 'compiler' => ( $Config::Config{'cc'} || 'cc' ) );
    print join( "\n", @{$compiler_messages} ) . "....Done\n";
    if ( !$compiler_status ) {
        print " ** Unrecoverable Error **\n";
        print "The C compiler is not functional and auto repair failed.\n";
        print "Perl module installs require a working C compiler.\n";
        print "Please repair the C compiler and try again.\n";
        print " **************************\n";
        exit 1;
    }
    local $ENV{'CFLAGS'};
    local $ENV{'CCFLAGS'};
    local $ENV{'OPTIMIZE'} = $Config::Config{'optimize'};
    if ( ref $preferred_flags ) {
        $ENV{'CCFLAGS'} = $ENV{'CFLAGS'} = join( ' ', @{$preferred_flags} );
        $ENV{'OPTIMIZE'} .= ' ' . join( ' ', @{$preferred_flags} );
    }

    local $ENV{'PERL_CPANM_HOME'};
    unshift @CPANM_ARGS, '--notest', '--verbose';
    unshift @CPANM_ARGS, '--local-lib=~/perl5' if $> != 0;
    $ENV{'PERL_CPANM_HOME'} = "$self->{'basedir'}/.cpanm";

    my $prev_umask = umask();
    umask(022);

    umask($prev_umask);

    my $install_success = 0;
    my $install_output;

    if ( !$self->{'hasperlexpect'} ) {
        print "** (Warning! Perl Expect and the expect binary are not installed!) **\n";
    }

    {
        my $name = 'cpanminus';

        print "Method: Using $name\n";
        my ( $exit_status, $install_output, $got_alarm );
        eval {
            local $SIG{'ALRM'} = sub {
                $got_alarm = 1;
                die "$name timed out";
            };
            alarm($INSTALL_TIMEOUT);    # one hour
            ( $exit_status, $install_output ) = cpanminus_installer( @CALL_CPANM, @CPANM_ARGS );

        };
        my $method_success = 1;
        if ($got_alarm) {
            print "$name failed with timeout\n\n";
            $method_success = 0;
        }
        elsif ($@) {
            print "$name failed with error: $@\n\n";
            $method_success = 0;
        }
        elsif ( $exit_status != 0 ) {
            print "$name failed with non-zero exit status: $exit_status\n\n";
            $method_success = 0;
        }
        if ($method_success) {
            $install_success = 1;
        }

    }

    if ( !$install_success ) {
        print "All available perl module install methods have failed\n";
    }

    return $install_output;
}

sub cpanminus_installer {
    my (@cmd) = @_;

    my $install_output;

    my $stdout = IO::Handle->new();

    my $pid = IPC::Open3::open3(
        undef, $stdout, '>&STDERR',    # .
        @cmd                           # .
    );
    while ( readline $stdout ) {
        print;
        $install_output .= $_;
    }
    close($stdout);

    waitpid( $pid, 0 );
    my $child_exit_status = $? >> 8;

    return ( $child_exit_status, $install_output );
}

sub is_namespace {
    my ($string) = @_;
    return 1 if $string =~ m{ \A \w+ (::\w+)* \z }xms;
    return;
}

1;
