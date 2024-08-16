package Cpanel::MysqlUtils::SlowQueryLog;

# cpanel - Cpanel/MysqlUtils/SlowQueryLog.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::SafeFile             ();
use Cpanel::StringFunc::File     ();
use Cpanel::MysqlUtils::Restart  ();
use Cpanel::MysqlUtils::Version  ();
use Cpanel::LoadFile             ();
use Cpanel::Logger               ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::ConfigFiles          ();

my $logger = Cpanel::Logger->new();

my $enabled_re_line = q<^\s*(?:log[_-]slow[_-]queries|slow[_-]query[_-]log\s*=\s*1.*)$>;

sub get_my_cnf {
    my $my_cnf_txt = Cpanel::LoadFile::loadfile( _get_my_cnf() ) || '';
    my @array      = split /\n/, $my_cnf_txt;
    return \@array;
}

sub get_slow_query_log_file {
    my $my_cnf_ref = get_my_cnf();

    foreach (@$my_cnf_ref) {

        # Match if this is a quoted string as the value.
        if (
            m/
            ^\s*
            (?:log[-_]slow[-_]queries|slow[-_]query[-_]log[-_]file) # log_slow_queries or slow_query_log_file
            \s*=\s* # = with white space on either side.
            (["']) # A Quote
            (\S[^'"]+?) # Non-white-space followed by as little as possible
            \1 # A closing quote
            \s* # possible white space.
            (?:\#|\Z) # Anchor on EOL or a comment.
            /x
        ) {
            return $2;
        }

        # Match if it's not quoted.
        if (
            m/
            ^\s*
            (?:log[-_]slow[-_]queries|slow[-_]query[-_]log[-_]file) # log_slow_queries or slow_query_log_file
            \s*=\s* # = with white space on either side.
            ([^ '"#][^'"#]+?) # Non-white-space followed by as little as possible
            \s* # possible white space.
            (?:\#|\Z) # Anchor on EOL or a comment.
            /x
        ) {
            return $1;
        }
    }

    return;
}

sub is_enabled {
    my $my_cnf_ref = get_my_cnf();

    # line by line simplifies the re
    foreach (@$my_cnf_ref) {
        if (m/$enabled_re_line/) {
            return 1;
        }

        if (m/^\s*log[-_]slow[-_]queries\s*=/) {
            return 1;
        }
    }
    return 0;
}

sub disable {
    my $current_mysqlver = Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default();
    my $my_cnf           = _get_my_cnf();

    # We try to remove both variants of the directives here because of how
    # the my.cnf file was updated previously.
    my $modified = 0;
    Cpanel::StringFunc::File::remlinefile_strict( $my_cnf, '^\s*slow-query-log' )   && $modified++;
    Cpanel::StringFunc::File::remlinefile_strict( $my_cnf, '^\s*slow_query_log' )   && $modified++;
    Cpanel::StringFunc::File::remlinefile_strict( $my_cnf, '^\s*log-slow-queries' ) && $modified++;
    Cpanel::StringFunc::File::remlinefile_strict( $my_cnf, '^\s*log_slow_queries' ) && $modified++;

    Cpanel::StringFunc::File::remlinefile_strict( $my_cnf, '^\s*long_query_time\s*=' )                    && $modified++;
    Cpanel::StringFunc::File::remlinefile_strict( $my_cnf, '^\s*long-query-time\s*=' )                    && $modified++;
    Cpanel::StringFunc::File::remlinefile_strict( $my_cnf, '^\s*set-variable\s*=\s*long_query_time\s*=' ) && $modified++;
    Cpanel::StringFunc::File::remlinefile_strict( $my_cnf, '^\s*set-variable\s*=\s*long-query-time\s*=' ) && $modified++;

    return $modified ? Cpanel::MysqlUtils::Restart::restart() : 1;
}

#TODO: Use Cpanel::Transaction::File::Raw for this.
sub enable {
    my ( $slow_query_log_file, $mysql_version ) = @_;

    $mysql_version = Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default() if !defined $mysql_version;

    my $my_cnf = _get_my_cnf();
    if ( !-e $my_cnf ) {
        $logger->warn("No $my_cnf .. creating..");
        Cpanel::FileUtils::TouchFile::touchfile($my_cnf);
    }
    my $ml = Cpanel::SafeFile::safeopen( \*MYC, '+<', $my_cnf );
    if ( !$ml ) {
        $logger->warn("Could not edit $my_cnf: $!");
        return;
    }

    my $modified = 0;
    my @MYCNF    = <MYC>;
    if ( !grep( /\[mysqld\]/, @MYCNF ) ) {
        print MYC "\n[mysqld]\n";
        _add_slow_query_directives( \*MYC, $slow_query_log_file, $mysql_version );
        $modified = 1;
    }
    else {
        if ( !grep( /$enabled_re_line/, @MYCNF ) ) {
            seek( MYC, 0, 0 );
            foreach my $line (@MYCNF) {
                print MYC $line;
                if ( $line =~ m/^\s*\[mysqld\]/ ) {
                    _add_slow_query_directives( \*MYC, $slow_query_log_file, $mysql_version );
                    $modified = 1;
                }
            }
            truncate( MYC, tell(MYC) );
        }
    }

    Cpanel::SafeFile::safeclose( \*MYC, $ml );
    Cpanel::MysqlUtils::Restart::restart() if $modified;

    return 1;
}

sub _add_slow_query_directives {
    my ( $fh, $slow_query_log_file, $mysql_version ) = @_;

    my $current_mysqlver = $mysql_version;
    $current_mysqlver = Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default() if !defined $current_mysqlver;

    my $directive;
    if ( Cpanel::MysqlUtils::Version::is_at_least( $current_mysqlver, '5.1' ) ) {
        $directive = 'slow-query-log=1';
    }
    else {
        $directive = 'log-slow-queries';
        if ( defined $slow_query_log_file ) {
            $directive = qq~log-slow-queries="$slow_query_log_file"~;
        }
    }

    if ( defined $slow_query_log_file ) {
        if ( Cpanel::MysqlUtils::Version::is_at_least( $current_mysqlver, '5.1' ) ) {
            print {$fh} map { "$_\n" } $directive, 'long-query-time=1', qq~slow-query-log-file="$slow_query_log_file"~;
        }
        else {
            print {$fh} map { "$_\n" } $directive, 'long-query-time=1';
        }
    }
    else {
        print {$fh} map { "$_\n" } $directive, 'long-query-time=1';
    }

    return;
}

sub _get_my_cnf {

    # MYSQL_CNF is defined in 11.44+
    return $Cpanel::ConfigFiles::MYSQL_CNF || '/etc/my.cnf';
}

1;
