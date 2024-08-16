package Cpanel::MysqlUtils::Statements;

# cpanel - Cpanel/MysqlUtils/Statements.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::MysqlUtils::Unquote      ();
use Cpanel::MysqlUtils::Quote        ();
use Cpanel::LoadModule               ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::MysqlUtils::Version      ();

#This does a "best-guess" attempt at renaming a DB within a MySQL command,
#ASSUMING that the DB:
#   - is not preceded by a period, and
#   - IS followed by a period
#
#This does NOT remove comments; do that first if it's a concern!
#

sub rename_db_in_command {
    my ( $db, $new_db, $stmt ) = @_;

    my ( $db_q, $new_db_q ) = map { Cpanel::MysqlUtils::Quote::quote_identifier($_) } ( $db, $new_db );

    #If the old DB name need not be quoted, then we remove all quoted
    #entities and search for the old DB name followed by a period.
    if ( !identifier_must_be_quoted($db) ) {
        $stmt = _alter_stripped_string(
            $stmt,
            _regexp_to_capture_any_quoted_entity(),
            sub { s[(?<! \. ) (\s*) (\Q$db\E) (?= \s* \.)][$1$new_db_q]xg },
        );
    }

    my $db_re = qr[
        (?<! \. ) (\s*)
        (\Q$db_q\E)
        (?= \s* \.)
    ]x;

    return _alter_stripped_string(
        $stmt,
        qr<($Cpanel::MysqlUtils::Unquote::QUOTED_STRING_REGEXP)>ox,
        sub { s<$db_re><$1$new_db_q>g },
    );
}

#cf. https://dev.mysql.com/doc/refman/5.5/en/identifiers.html
sub identifier_must_be_quoted {
    my $id = shift;

    return 1 if !length $id;

    #If it's only numerals, we must quote.
    return 1 if $id !~ tr<0-9><>c;

    #No need to quote if it's only these characters.
    while ( $id =~ m<([^0-9a-zA-Z\$_]+)>g ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::UTF8');
        my $codes_ar = Cpanel::UTF8::get_unicode_as_code_point_list($1);

        return 1 if grep { $_ < 0x80 } @$codes_ar;
    }

    return 0;
}

sub replace_in_command_outside_quoted_strings {
    my ( $pattern, $new_text, $command ) = @_;

    return _alter_stripped_string(
        $command,
        _regexp_to_capture_any_quoted_entity(),
        sub { s<$pattern><$new_text>g },
    );
}

my $quoted_regexp_part = join(
    '|',
    $Cpanel::MysqlUtils::Unquote::QUOTED_IDENTIFIER_REGEXP,
    $Cpanel::MysqlUtils::Unquote::QUOTED_STRING_REGEXP,
);

sub _regexp_to_capture_any_quoted_entity_or_comment {
    return qr<(
        $quoted_regexp_part
        |
        /\* (?!!) .*? \*/
    )>sx;
}

sub _regexp_to_capture_any_quoted_entity {
    return qr<($quoted_regexp_part)>;
}

#$strip_re should capture ONE thing.
#$alter_cr will have the string as $_.
sub _alter_stripped_string {
    my ( $string, $strip_re, $alter_cr ) = @_;

    my @replaced_strings;

    my $random_bit = rand();
    $random_bit =~ tr<0-9><>cd;
    my $cp_string_prefix = "__CP_STRING__$random_bit\__";

    my $count = 0;

    $string =~ s<$strip_re><
        $count++;
        push @replaced_strings, $1;
        $cp_string_prefix . ($count - 1);
    >eg;

    $alter_cr->() for $string;    #set $_ to the string

    $string =~ s<$cp_string_prefix(\d+)><$replaced_strings[$1]>g;

    return $string;
}

#Pass in either a DB handle or a version string.
sub strip_comments_for_version {
    my ( $version, $stmt ) = @_;

    if ( UNIVERSAL::isa( $version, 'DBI::db' ) ) {
        ($version) = Cpanel::MysqlUtils::MyCnf::Basic::get_server_version($version);
    }

    #Ensure that we ignore any quoted strings (values or identifiers)
    #*and* that we ignore any normal comments. This is important because
    #conditional comments can enclose regular comments. (cf. CPANEL-14977)
    my $pattern_re = _regexp_to_capture_any_quoted_entity_or_comment();

    my $max_mysql = _max_mysql_for_comment($version);

    return _alter_stripped_string(
        $stmt,
        $pattern_re,
        sub {
            #Strip out stuff that the given MySQL version can't parse ...
            s{
                /\* ! ([0-9]+)
                \s+
                (.*?)
                \s*
#                (?:
                    \*/
#                    |
#                    /\*
#                )
            }{
                ($1 < $max_mysql) ? $2 : q<>
            }xegs;

            # These are potentially unsafe so they were
            # removed in the review process and the tests
            # did not seem to need them
            #
            #C-style
            # s</\*.*?\*/><>g;
            #End-of-line
            # s<(?:#|--\s)[^\n]*><>g;
        },
    );
}

sub _max_mysql_for_comment {
    my ($version) = @_;

    if ( 1 == $version =~ tr<.><> ) {
        $version .= ".99";
    }

    return Cpanel::MysqlUtils::Version::string_to_number($version);
}

#Checks to see if the given statement begins with a CREATE,
#disregarding conditional comments and case.
sub is_create_statement {

    # $_[0]: statement
    return ( $_[0] =~ m<\A\s*(?:/\*!\d+\s+)?CREATE(?:\*/|\s+)>i ) ? 1 : 0;
}

#cf. http://dev.mysql.com/doc/refman/5.5/en/user-variables.html
#
my $MYSQL_VAR_NAME_REGEXP = qq{(?^x:
    [a-zA-Z0-9._\$]+     #unquoted can have alphanums and: . _ \$
    |
    $Cpanel::MysqlUtils::Unquote::QUOTED_IDENTIFIER_REGEXP
    |
    $Cpanel::MysqlUtils::Unquote::QUOTED_STRING_REGEXP
)};

#Returns key/value or empty. These return values are NOT de-quoted
#because they might be @variables, or '@variable',
#and we need to be able to distinguish.
#
sub parse_set_statement {

    # $_[0]: statement
    my ( $key, $value ) = (
        $_[0] =~ m<
        \A
        \s*
        (?:/\*!\d+\s+)?
        SET
        \s+
        (
            \@{0,2}     #user-defined variables are prefixed with @ && there can be up to 2 ats
            $MYSQL_VAR_NAME_REGEXP
        )
        \s*
        =
        \s*
        (
            \S+
            |
            $Cpanel::MysqlUtils::Unquote::QUOTED_STRING_REGEXP
        )
    >xi
    );

    return $key ? ( $key, $value ) : ();
}

1;
