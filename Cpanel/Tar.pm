package Cpanel::Tar;

# cpanel - Cpanel/Tar.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cwd                   ();
use Cpanel::CachedCommand ();

# As of CentOS 6 these are always supported, so there’s no need to check.
use constant OPTIMIZATION_OPTIONS => (
    '--sparse',
    '--blocking-factor' => 200,
);

my $logger;

#For mocking.
our $_TEST_TAR_BIN;

#This is only used in testing and should probably stay that way.
#Use load_tarcfg() instead.
our $tarcfg = {};

#This doesn't take any parameters; it returns the program path and minimum
#arguments that should always be used when creating a tar archive.
#
#Return values are: ( $program, @args )
#
sub command_to_create_to_stdout {
    my $cfg = load_tarcfg();

    return (
        $cfg->{'bin'},
        '--create',
        ( $cfg->{'dash_b'} ? '--blocking-factor=200' : () ),
        ( '--file' => '-' ),
    );
}

sub load_tarcfg {
    return $tarcfg if !$_TEST_TAR_BIN && exists $tarcfg->{'bin'};

    $tarcfg->{'bin'} = $_TEST_TAR_BIN || ( -x '/bin/gtar' ? '/bin/gtar' : '/bin/tar' );    # prefer gnutar

    my $tar_version = Cpanel::CachedCommand::cachedcommand( $tarcfg->{'bin'}, '--version' ) // '';
    my $tar_help    = Cpanel::CachedCommand::cachedcommand( $tarcfg->{'bin'}, '--help' )    // '';

    $tarcfg->{'working_env'}              = 1;                                             # tar 1.13.25 will segfault with TAR_OPTIONS set but thats not an issue anymore
    $tarcfg->{'no_same_owner'}            = index( $tar_help, 'no-same-owner' ) > -1            ? '--no-same-owner'       : '-o';
    $tarcfg->{'same_owner'}               = index( $tar_help, 'same-owner' ) > -1               ? '--same-owner'          : ();
    $tarcfg->{'no_same_permissions'}      = index( $tar_help, 'no-same-permissions' ) > -1      ? '--no-same-permissions' : '';
    $tarcfg->{'no_wildcards_match_slash'} = index( $tar_help, 'no-wildcards-match-slash' ) > -1 ? 1                       : 0;
    $tarcfg->{'dash_T'}                   = index( $tar_help, '-T' ) > -1                       ? 1                       : 0;
    $tarcfg->{'dash_S'}                   = index( $tar_help, '-S' ) > -1                       ? 1                       : 0;
    $tarcfg->{'dash_j'}                   = 1;                                             # All versions of tar under centos6+ support this
    $tarcfg->{'dash_b'}                   = 1;                                             # All versions of tar under centos6+ support this
    $tarcfg->{'dashdash_utc'}             = index( $tar_help, '--utc' ) > -1      ? 1 : 0;
    $tarcfg->{'dashdash_fulltime'}        = index( $tar_help, '--fulltime' ) > -1 ? 1 : 0;
    $tarcfg->{'dashdash_unquote'}         = index( $tar_help, '--unquote' ) > -1  ? 1 : 0;
    $tarcfg->{'type'}                     = 'gnu';
    if ( index( $tar_help, 'bsdtar' ) > -1 ) { $tarcfg->{'no_same_owner'} = '-o'; $tarcfg->{'dash_T'} = 1; $tarcfg->{'type'} = 'bsd'; }

    return $tarcfg;
}

sub checkperm {
    my ($args)  = @_;
    my $tarcfg  = load_tarcfg();
    my $tar_bin = $tarcfg->{'bin'};
    my $caller  = $args->{'caller'};

    my $success_message;
    my $cwd;

    if ( !$tar_bin ) {
        require Cpanel::Logger;
        $logger ||= Cpanel::Logger->new();
        $logger->warn('Unable to locate suitable tar binary');
        return ( 0, 'Unable to locate suitable tar binary' );
    }
    else {

        # Some admins think it's a good thing to lock down permissions, but don't lock down tar
        my $orig_tar_bin = $tar_bin;

        # Symlinks are always executable, need to check the actual binary
        if ( -l $tar_bin ) {
            my $path = $tar_bin;
            $path =~ s/[^\/]+$//;
            $tar_bin = readlink $tar_bin;
            $cwd     = Cwd::fastcwd();
            chdir $path or do {
                require Cpanel::Logger;
                $logger ||= Cpanel::Logger->new();
                $logger->warn("Failed to chdir: $!");    # Failure here is OK as one of the following conditions will verify it.
            };
        }
        if ( -e $tar_bin ) {
            my $tar_perms = sprintf( '%04o', ( stat(_) )[2] & 01111 );
            if ( $tar_perms ne '0111' ) {

                # Only chmod a file that is already owned by the EUID (hopefully that's root)
                if ( -o $tar_bin ) {
                    require Cpanel::Logger;
                    $logger ||= Cpanel::Logger->new();
                    $logger->info("Setting permissions of $tar_bin to 0755");
                    if ( chmod( 0755, $tar_bin ) ) {
                        $success_message = "Permissions of $tar_bin set to 0755";
                    }
                    else {
                        require Cpanel::Logger;
                        $logger ||= Cpanel::Logger->new();
                        $logger->warn("Failed to set 0755 permissions on $tar_bin: $!");
                        return ( 0, "Failed to set 0755 permissions on $tar_bin" );
                    }
                }
                else {
                    require Cpanel::Logger;
                    $logger ||= Cpanel::Logger->new();

                    $logger->warn("Invalid permissions on $orig_tar_bin, tar should be executable by all users. Skipping permision change due to ownership.");
                    return ( 0, "Invalid permissions on $orig_tar_bin, tar should be executable by all users. Skipping permision change due to ownership." );
                }
            }
        }
        else {
            require Cpanel::Logger;
            $logger ||= Cpanel::Logger->new();

            $logger->warn("Unable to locate suitable tar binary! $orig_tar_bin does not exist.");
            return ( 0, "Unable to locate suitable tar binary! $orig_tar_bin does not exist." );
        }
    }

    #Restore the cwd that we had when we started this function.
    chdir $cwd if $cwd;

    return ( 1, $success_message || 'Tar check successful' );
}

# This assumes tar was run with $ENV{'LANG'} = 'C';
sub is_fatal_tar_stderr_output {
    my ($output) = @_;

    my @known_fatals = ( 'does not look like a tar archive', 'error is not recoverable', 'not in gzip format', 'is not a bzip2 file' );

    return ( grep { $output =~ m{$_}i } @known_fatals ) ? 1 : 0;
}

1;
