package Whostmgr::Whm5;

# cpanel - Whostmgr/Whm5.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) - not fully vetted for warnings

use Whostmgr::Remote             ();
use Cpanel::Fcntl                ();
use Whostmgr::Transfers::Version ();

## This package hosts code refactored from whostmgr5.pl

# These are arguments that *may* be given to pkgacct, not ones that
# “should” or “will”. Hence, despite any resemblance between this
# list and ones for worker-node backups, we should *not* deduplicate
# such lists with this one.
#
my @_PKGACCT_BOOLEAN_OPTS = qw(
  split
  skipacctdb
  skipbwdata
  incremental
  skipapitokens
  skipauthnlinks
  skipdnssec
  skipdnszones
  skipftpusers
  skiplinkednodes
  skiplogs
  skipresellerconfig
  skipshell
  skipvhosttemplates
);

sub remote_get_whm_servtype {
    my ( $remote_obj, $servtype ) = @_;
    my ( $status,     $result )   = (
        $remote_obj->remoteexec(
            "txt"          => "Fetching WHM Version",
            "returnresult" => 1,
            "cmd"          => "test -d /usr/local/cpanel && cat /usr/local/cpanel/version; echo"
        )
    )[ $Whostmgr::Remote::STATUS, $Whostmgr::Remote::RESULT ];

    if ($status) {
        chomp $result;
        my ($version) = split /-/, $result, 2;
        $servtype = find_WHM_version($version);
    }
    else {
        $servtype = 'WHM11241';
    }
    return $servtype;
}

sub find_WHM_version {
    my $version = shift;

    if ( ( ver_cmp( $version, '4.4' ) == -1 ) or ( ver_cmp( $version, '4.4' ) == 0 ) ) {
        return 'preWHM45';
    }
    elsif ( ( ver_cmp( $version, '11.18.9' ) == -1 ) or ( ver_cmp( $version, '11.18.9' ) == 0 ) ) {
        return 'WHM45';
    }
    elsif ( ( ver_cmp( $version, '11.19.9' ) == -1 ) or ( ver_cmp( $version, '11.19.9' ) == 0 ) ) {
        return 'WHM1119';
    }
    elsif ( ( ver_cmp( $version, '11.22.9' ) == -1 ) or ( ver_cmp( $version, '11.22.9' ) == 0 ) ) {
        return 'WHM1120';
    }
    elsif ( ( ver_cmp( $version, '11.23.9' ) == -1 ) or ( ver_cmp( $version, '11.23.9' ) == 0 ) ) {
        return 'WHM1123';
    }
    elsif ( ( ver_cmp( $version, '11.24.0' ) == -1 ) or ( ver_cmp( $version, '11.24.0' ) == 0 ) ) {
        return 'WHM1124';
    }
    elsif ( ( ver_cmp( $version, '11.24.1' ) == -1 ) or ( ver_cmp( $version, '11.24.1' ) == 0 ) ) {
        return 'WHM11241';
    }
    elsif ( ( ver_cmp( $version, '11.53.0.0' ) == -1 ) or ( ver_cmp( $version, '11.29.0.0' ) == 0 ) ) {
        return 'WHM1130';
    }
    elsif ( ( ver_cmp( $version, '11.64.0.30' ) == -1 ) or ( ver_cmp( $version, '11.53.0.0' ) == 0 ) ) {
        return 'WHM1154';
    }
    elsif ( ver_cmp( $version, '11.64.0.30' ) >= 0 ) {
        return 'WHM1164';
    }
    else {
        return 'WHM11241';
    }
}

sub ver_cmp {
    my @tokens_a = split /\./, shift;
    my @tokens_b = split /\./, shift;

    while ( @tokens_a || @tokens_b ) {
        my $token_a = @tokens_a ? shift @tokens_a : 0;
        my $token_b = @tokens_b ? shift @tokens_b : 0;

        return $token_a <=> $token_b if $token_a != $token_b;
    }

    return 0;
}

sub splitfile_recombine {
    my ( $basedir, $outfile, $ar_ASSEMBLELIST ) = @_;

    my $open_mode = Cpanel::Fcntl::or_flags(qw( O_WRONLY O_TRUNC O_CREAT ));
    sysopen( my $FINALFILE, "$basedir/$outfile", $open_mode, 0600 );

    my $partn = 1;
    foreach my $part ( sort bylastnum @$ar_ASSEMBLELIST ) {
        print "Archive Recombine in progress (part “$part” ${partn})…\n";
        if ( !-e $part ) {
            print "Tarball file “$part” is missing!\n";
            ## TODO: move the exit outside
            return 0;
        }
        if ( open( my $P, '<', $part ) ) {
            while ( sysread( $P, my $buff, 65535 ) ) {
                print $FINALFILE $buff;
            }
            close($P);
            unlink($part);    ## cpdev!
        }
        else {
            print "Problem a fatal error, could not open “$part”… trying to recover…";
        }
        $partn++;
        print "Done\n";
    }
    close($FINALFILE);
    print "Tarball recombine ok!\n";
    return 1;
}

sub bylastnum {
    $a =~ /(\d+)$/;
    my $anum = $1;
    $b =~ /(\d+)$/;
    my $bnum = $1;
    return $anum <=> $bnum;
}

sub get_pkgcmd_as_array {
    my ( $pkgacct, $user, $opts ) = @_;

    $opts //= {};

    my $scriptdir = Whostmgr::Remote->remotescriptdir( $opts->{'servtype'} );

    if ( $opts->{'servtype'} eq 'sp*era' && exists $opts->{'hr_sphera'} ) {
        return ( $user, $opts->{'tarroot'}, @{ $opts->{'hr_sphera'} }{qw/sphera_user sphera_password sphera_host/} );
    }

    my @args;

    if ( Whostmgr::Transfers::Version::servtype_version_compare( $opts->{'servtype'}, '>=', '11.20' ) ) {
        my $skiphomedir = $opts->{'skiphomedir'} ? $opts->{'skiphomedir'} : 0;

        if ( Whostmgr::Transfers::Version::servtype_version_compare( $opts->{'servtype'}, '>=', '11.24' ) && $opts->{'can_stream'} && $opts->{'whmuser'} && $opts->{'whmpass'} ) {
            $skiphomedir = 1;
        }

        if ( Whostmgr::Transfers::Version::servtype_version_compare( $opts->{'servtype'}, '>=', '11.30' ) && $opts->{'use_backups'} ) {
            push @args, '--use_backups';
        }

        if ( Whostmgr::Transfers::Version::servtype_version_compare( $opts->{'servtype'}, '>=', '11.54' ) && $opts->{'serialized_output'} ) {
            push @args, '--serialized_output';
        }

        if ($skiphomedir) {
            push @args, '--skiphomedir';
        }
        elsif ( Whostmgr::Transfers::Version::servtype_version_compare( $opts->{'servtype'}, '>=', '11.20' ) && Whostmgr::Transfers::Version::servtype_version_compare( $opts->{'servtype'}, '<', '11.24' ) ) {
            push @args, qw/--version 3/;
        }

        ## note: if this is moved outside the WHM-only block, add "&& $opts->{'servtype'} =~ /^WHM/"
        if ( $opts->{'roundcube'} ) {
            ## TODO for case 49123
            #push @args, '--roundcube', $opts->{'roundcube'};
        }
    }

    push @args, $user, $opts->{'tarroot'};

    if ( $opts->{'compressionsetting'} ) {
        push @args, "--$opts->{'compressionsetting'}";
    }

    if ( $opts->{'mysqlver'} ) {
        push @args, '--mysql', $opts->{'mysqlver'};
    }

    if ( $opts->{'dbbackup_mysql'} ) {
        push @args, '--dbbackup_mysql', $opts->{'dbbackup_mysql'};
    }

    if ( $opts->{'servtype'} =~ m{^(?:plesk|ensim|directadmin)}i ) {
        push @args, '--allow-multiple';
    }

    foreach my $arg (@_PKGACCT_BOOLEAN_OPTS) {
        push @args, "--$arg" if $opts->{$arg};
    }

    my $cmd = $pkgacct =~ m{^/} ? $pkgacct : "$scriptdir/$pkgacct";
    my @cmd = ( $cmd, @args );

    if ( $opts->{'low_priority'} ) {
        unshift @cmd, "$scriptdir/pkgacct-wrapper";
    }

    return @cmd;
}

sub get_pkgcmd {
    my ( $pkgacct, $user, $opts ) = @_;

    my @pkgcmd = get_pkgcmd_as_array( $pkgacct, $user, $opts );

    return join( ' ', @pkgcmd );
}

1;
