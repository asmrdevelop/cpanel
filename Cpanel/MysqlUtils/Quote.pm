
# cpanel - Cpanel/MysqlUtils/Quote.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::MysqlUtils::Quote;

use strict;

#cf. http://dev.mysql.com/doc/refman/5.1/en/string-literals.html
#BUT: the \b and \t escapes are not required and mysql's
#real_escape_string does not them, so we don't do them either.
my @_orig_QUOTE_ESCAPE_CHARACTER = (
    "\0"     => '0',
    q(')     => q('),
    q(")     => q("),
    "\x{a}"  => 'n',
    "\x{d}"  => 'r',
    "\x{1a}" => 'Z',
    '\\'     => '\\',
);

my @unquote_unescape = (
    b => "\b",
    t => "\t",
);

our %QUOTE_ESCAPE_CHARACTER;

our @PATTERN_ESCAPE_CHARACTERS = qw( \ _ % );

our $PATTERN_ESCAPE_REGEXP_PART;
our $QUOTE_REGEXP_PART;
our $QUOTE_PATTERN_REGEXP_PART;
our $UNQUOTE_PATTERN_REGEXP_PART;
our $UNQUOTE_REGEXP_PART;

our %UNQUOTE_ORIGINAL_CHARACTER;
our $DID_QUOTE_INIT = 0;

#
# Build these only when needed to make perlcc happy
#
sub quote_init {
    return if $DID_QUOTE_INIT;
    $DID_QUOTE_INIT = 1;    # extra safety in case the glob is copied.

    %QUOTE_ESCAPE_CHARACTER = @_orig_QUOTE_ESCAPE_CHARACTER;

    $PATTERN_ESCAPE_REGEXP_PART = join( '', map { quotemeta($_) } @PATTERN_ESCAPE_CHARACTERS );

    $QUOTE_REGEXP_PART = join( '', map { quotemeta($_) } keys %QUOTE_ESCAPE_CHARACTER );

    @QUOTE_ESCAPE_CHARACTER{@PATTERN_ESCAPE_CHARACTERS} = @PATTERN_ESCAPE_CHARACTERS;

    $QUOTE_PATTERN_REGEXP_PART = join( '', map { quotemeta($_) } keys %QUOTE_ESCAPE_CHARACTER );

    #We have to be able to UN-escape these...
    %QUOTE_ESCAPE_CHARACTER = (
        %QUOTE_ESCAPE_CHARACTER,
        reverse @unquote_unescape,
    );

    $UNQUOTE_PATTERN_REGEXP_PART = join( '', map { quotemeta($_) } values %QUOTE_ESCAPE_CHARACTER );

    %UNQUOTE_ORIGINAL_CHARACTER = reverse %QUOTE_ESCAPE_CHARACTER;

    %QUOTE_ESCAPE_CHARACTER = (
        @_orig_QUOTE_ESCAPE_CHARACTER,
        reverse @unquote_unescape,
    );

    $UNQUOTE_REGEXP_PART = join( '', map { quotemeta($_) } values %QUOTE_ESCAPE_CHARACTER );

    @QUOTE_ESCAPE_CHARACTER{@PATTERN_ESCAPE_CHARACTERS} = @PATTERN_ESCAPE_CHARACTERS;

    {
        no warnings 'redefine';
        *quote_init = sub { };
    }

    return;
}

sub quote {
    my ($copy) = @_;
    return 'NULL'      if !defined $copy;
    return qq{'$copy'} if $copy !~ tr<\0'"\x{a}\x{d}\x{1a}\\><>;

    quote_init();
    $copy =~ s{([$QUOTE_REGEXP_PART]{1})}{\\$QUOTE_ESCAPE_CHARACTER{$1}}og;
    return qq{'$copy'};
}

sub quote_conf_value {    ## no critic qw(Subroutines::RequireArgUnpacking)
    return $_[0] if $_[0] !~ tr/"\n\t\0\\//;
    my ($string) = @_;
    $string =~ s/\\/\\\\/g;    # Escape backslashes
    $string =~ s/\0/\\0/g;     # Escape nulls
    $string =~ s/"/\\"/g;      # Escape double quotes
    $string =~ s/\n/\\n/g;     # Escape newlines
    $string =~ s/\r/\\r/g;     # Escape line feeds
    $string =~ s/\t/\\t/g;     # Escape tabs
    return $string;
}

#Only escapes pattern characters; does NOT quote.

sub quote_pattern_identifier {
    my ($copy) = @_;

    return 'NULL' if !defined $copy;
    return "`$copy`" if $copy !~ tr/`_%//;
    $copy =~ s{`}{``}g  if index( $copy, '`' ) > -1;
    $copy =~ s{_}{\\_}g if index( $copy, '_' ) > -1;
    $copy =~ s{%}{\\%}g if index( $copy, '%' ) > -1;
    return "`$copy`";
}

sub quote_pattern {
    my ($copy) = @_;

    return 'NULL'      if !defined $copy;
    return qq{'$copy'} if $copy !~ tr/\0'"\x{a}\x{d}\x{1a}\\_%//;

    quote_init();
    $copy =~ s{([$QUOTE_PATTERN_REGEXP_PART]{1})}{\\$QUOTE_ESCAPE_CHARACTER{$1}}og;
    return qq{'$copy'};
}

sub escape_pattern {
    my ($copy) = @_;

    quote_init();
    $copy =~ s{([$PATTERN_ESCAPE_REGEXP_PART])}{\\$1}og;

    return $copy;
}

#Only unescapes pattern characters; does NOT unquote.
sub unescape_pattern {
    my ($copy) = @_;

    quote_init();
    $copy =~ s{\\([$PATTERN_ESCAPE_REGEXP_PART])}{$1}og;

    return $copy;
}

sub quote_identifier {
    my ($copy) = @_;

    return '' if !defined $copy;
    return "`$copy`" if $copy !~ tr/`_%//;
    $copy =~ s{`}{``}g;
    return "`$copy`";
}

sub quote_db_and_name {
    my ( $db, $name ) = @_;
    return join( '.', map { quote_identifier($_) } $db, $name );
}

sub safesqlstring {
    return ( $_[0] !~ tr/\\\0\n\r'"\?\x1a// ? $_[0] : substr( quote( $_[0] ), 1, -1 ) );
}

1;
