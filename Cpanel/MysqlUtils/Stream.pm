package Cpanel::MysqlUtils::Stream;

# cpanel - Cpanel/MysqlUtils/Stream.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use IPC::Open3      ();
use Cpanel::DbUtils ();
use Cpanel::Waitpid ();

sub stream_mysqldump_to_filehandle {
    my ($args) = @_;

    my $mysqldump = Cpanel::DbUtils::find_mysqldump();

    local $ENV{'MYSQL_PWD'} = $args->{'dbpass'};

    my $wfh;
    my $rfh;
    my $pid = IPC::Open3::open3(
        $wfh, $rfh, ">/dev/null",
        $mysqldump,
        '--no-defaults',
        '-u', $args->{'dbuser'},
        '-h', $args->{'dbhost'},
        ( $args->{'dbport'} ? ( '--port', $args->{'dbport'} ) : () ),
        @{ $args->{options} },
        '--',
        $args->{'db'},
    );

    close($wfh);

    while ( my $data = <$rfh> ) {
        print { $args->{'filehandle'} } $data;
    }

    close($rfh);
    Cpanel::Waitpid::sigsafe_blocking_waitpid($pid);
    return 1;
}

my $mysql_bin;

sub stream_filehandle_to_mysql {
    my ($args) = @_;

    $mysql_bin ||= Cpanel::DbUtils::find_mysql();

    my $wfh;
    my $pid = IPC::Open3::open3(
        $wfh, ">&STDERR", ">/dev/null",
        $mysql_bin,
        '--force',
        $args->{'db'},
    );

    my $fh = $args->{'filehandle'};
    while ( my $line = <$fh> ) {
        print {$wfh} $line;
    }
    print {$wfh} "\nFLUSH PRIVILEGES;\n";
    close($wfh);
    Cpanel::Waitpid::sigsafe_blocking_waitpid($pid);

    return 1;

}

1;
