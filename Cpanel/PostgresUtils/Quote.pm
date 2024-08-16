package Cpanel::PostgresUtils::Quote;

# cpanel - Cpanel/PostgresUtils/Quote.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Context ();

#This funny way of passing in the DB name is apparently the only way
#pg_restore < 9.3 can restore to DBs whose names contain the “=” sign.
#
#The issue is that libpq interprets “=” in the dbname as part of a
#connection information string. This is *kind* of documented:
#
#http://www.postgresql.org/docs/9.2/static/libpq-connect.html#LIBPQ-CONNECT-DBNAME
#(cf. “In certain contexts, the value is checked for extended formats …”)
#
#Even though the above is for PostgreSQL 9.2, and there is no equivalent
#in docs for prior versions, this does appear to work with the 9.0.18
#pg_dump and pg_restore that we’re shipping as of October 2015.
#
#Once we ship clients that are >= 9.3 we can(/should?) switch to:
#
#   --dbname => postgres:///$uri_encoded_dbname
#
sub dbname_command_args {
    my ($name) = @_;

    Cpanel::Context::must_be_list();

    return '--dbname' => pg_dump_dbname_arg($name);
}

sub pg_dump_dbname_arg {
    my ($name) = @_;

    return 'dbname=' . quote_conninfo($name);
}

#Useful for specifying database names and the like at the command line.
#cf. http://www.postgresql.org/docs/8.1/static/libpq.html#LIBPQ-CONNECT
sub quote_conninfo {
    my ($str) = @_;

    return sprintf q<'%s'>, $str =~ s<([\\'])><\\$1>gr;
}

sub quote_identifier {
    my ($string) = @_;

    return '' if !defined $string;
    return qq{"$string"} if $string !~ tr/\"//;
    $string =~ s/"/""/g;
    return qq{"$string"};
}

sub unquote_identifier {
    my ($str) = @_;

    $str =~ s{\A"}{};
    $str =~ s{"\z}{};

    if ( index( $str, '"' ) != -1 ) {
        $str =~ s{""}{"}g;
    }

    return $str;
}

#We use "escape" string constants (with a leading E) since PostgreSQL always
#parses these the same way; the parsing of "normal" string constants depends
#on the server's "standard_conforming_strings" configuration option.
#
#cf. http://www.postgresql.org/docs/8.4/static/sql-syntax-lexical.html
sub quote {
    my ($string) = @_;

    return 'NULL'                 if !defined $string;
    return q{E'} . $string . q{'} if $string !~ tr/\0'\\//;

    $string =~ s/(?=[\\\'])/\\/g;

    #"The character with the code zero cannot be in a string constant."
    #(cf. link above)
    #
    #Why is this in here?
    $string =~ s{\0}{\\0}g;

    return q{E'} . $string . q{'};
}

my %unquote_escapes;

#PostgreSQL has several different ways of quoting. This logic parses the variant
#that this module creates.
sub unquote_e {
    my ($string) = @_;

    return undef if $string eq 'NULL';

    my ($str) = ( $string =~ m{\A[eE]'(.*)'\z}s ) or do {
        die "invalid “E” string: $string";
    };

    if ( !%unquote_escapes ) {
        %unquote_escapes = (
            b => "\x08",
            f => "\x0c",
            n => "\x0a",
            r => "\x0d",
            t => "\x09",
        );
    }

    $str =~ s{''}{\\'}g;
    $str =~ s{\\(x[0-9a-fA-F]{1,2}|[0-7]{1,3}|.)}{_unquote_e_replacer()}eg;

    return $str;
}

#NOTE: Depends on $1
sub _unquote_e_replacer {
    if ( exists $unquote_escapes{$1} ) {
        return $unquote_escapes{$1};
    }
    if ( substr( $1, 0, 1 ) =~ tr{0-7}{} ) {
        return chr oct $1;
    }
    if ( ( length($1) > 1 ) && substr( $1, 0, 1 ) eq 'x' ) {
        return chr hex substr( $1, 1 );
    }

    return $1;
}

1;
