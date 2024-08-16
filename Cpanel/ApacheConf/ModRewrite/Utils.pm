package Cpanel::ApacheConf::ModRewrite::Utils;

# cpanel - Cpanel/ApacheConf/ModRewrite/Utils.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::ApacheConf::ModRewrite::Utils

=head1 SYNOPSIS

    use Cpanel::ApacheConf::ModRewrite::Utils ();

    #cf. Apache httpd modules/mappers/mod_rewrite.c
    my @args = Cpanel::ApacheConf::ModRewrite::Utils::parseargline($text);

    #Safeguards against Perl’s weird handling of m<>.
    my $yn = Cpanel::ApacheConf::ModRewrite::Utils::regexp_str_match(
        '^haha',
        'This won’t match.',
        'nocase',   #optional
    );

    my @flags = Cpanel::ApacheConf::ModRewrite::Utils::split_flags('[foo,bar]');

=cut

use strict;
use warnings;

use Try::Tiny;

use Cpanel::C_StdLib  ();    # PPI USE OK - used in regex /e below
use Cpanel::Context   ();
use Cpanel::Exception ();

#A port of the logic from modules/mappers/mod_rewrite.c
#in the Apache httpd source tree.
#
#Notable differences:
#   - This returns the arguments themselves.
#   - This parses arbitrarily many arguments.
#   - This unescapes spaces. (NOTE!)
#
sub parseargline {
    my ($line) = @_;

    Cpanel::Context::must_be_list();

    #forgiveness - as in mod_rewrite.c
    my $offset = _skip_spaces_at( $line, 0 );

    my @args;

    while ( $offset < length $line ) {
        my $arg;
        ( $offset, $arg ) = _skip_arg_at( $line, $offset );

        push @args, $arg;

        $offset = _skip_spaces_at( $line, $offset );
    }

    if ( @args < 2 ) {
        die "bad mod_rewrite argument line ($line): at least two arguments are required!";
    }

    return @args;
}

sub regexp_str_match {
    my ( $re_str, $test_value, @attrs ) = @_;

    my $nocase = grep { $_ eq 'nocase' } @attrs;

    #Perl treats a match against an empty pattern as something wildly
    #different from what you’d expect.
    if ( $re_str eq q<> ) {
        $re_str = '.*';
    }

    my $re;
    try { $re = $nocase ? qr<$re_str>i : qr<$re_str> }
    catch {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,Perl] regular expression: [_2]', [ $re_str, $_ ] );
    };

    return $test_value =~ m<$re> ? 1 : 0;
}

sub split_flags {
    my ($flags_txt) = @_;

    return if !length $flags_txt;

    Cpanel::Context::must_be_list();

    $flags_txt =~ m<\A\[(.*)\]\z> or do {
        die Cpanel::Exception::create( 'InvalidParameter', '[asis,mod_rewrite] flags require enclosing brackets.' );
    };

    return split m<,>, $1;
}

sub escape_for_stringify {
    my ($str) = @_;

    my $quote;

    if ( substr( $str, -1 ) eq '\\' ) {
        die "mod_rewrite’s parseargline() format can’t encode a string that ends with “\\”!";
    }

    #parseargline() will assume that, the first time it sees the opening
    #quote character after the opening, that’s the end of the string.
    #It doesn’t care whether the quote is backslash-escaped or not. This is
    #*probably* a bug, but for now we’ll roll with it.
    if ( substr( $str, 0, 1 ) eq q<'> ) {
        _cannot_encode($str) if $str =~ tr<"><>;
        $quote = '"';
    }
    elsif ( substr( $str, 0, 1 ) eq q<"> ) {
        _cannot_encode($str) if $str =~ tr<'><>;
        $quote = q<'>;
    }

    #Even when quoted, we apparently have to do this in order to round-trip
    #reliably when “\ ” is actually in the encoded string.
    #It’s slow to use isspace() here, but it avoids duplication.
    #If we need speed, we can revisit this.
    $str =~ s<(.)><Cpanel::C_StdLib::isspace($1) ? "\\$1" : $1>ge;

    if ($quote) {
        $str .= $quote;
        substr( $str, 0, 0 ) = $quote;
    }

    return $str;
}

#----------------------------------------------------------------------

sub _cannot_encode {
    my ($str) = @_;

    die "mod_rewrite’s parseargline() format can’t encode the string “$str”!";
}

sub _skip_spaces_at {
    my ( $line, $offset ) = @_;

    $offset ||= 0;

    #This was faster than setting pos() and doing a \G regexp match
    #when benchmarked during development.
    $offset++ while substr( $line, $offset, 1 ) =~ tr< \t\x0a-\x0d><>;    # inline Cpanel::C_StdLib::isspace;

    return $offset;
}

sub _skip_arg_at {
    my ( $line, $offset ) = @_;

    my $quote = substr( $line, $offset, 1 );
    if ( $quote eq '\'' || $quote eq '"' ) {
        $offset++;
    }
    else {
        undef $quote;
    }

    my $start_offset = $offset;
    my $arg;

    my $char;
    while ( $offset < length $line ) {
        $char = substr( $line, $offset, 1 );
        if ($quote) {
            last if $char eq $quote;
        }
        else {
            last if $char =~ tr< \t\x0a-\x0d><>;    # inline Cpanel::C_StdLib::isspace;;
        }

        #This is *just* skipping over the space;
        #it doesn’t imply anything about how the backslash gets handled
        #down the line.
        if ( $char eq '\\' && substr( $line, 1 + $offset, 1 ) =~ tr< \t\x0a-\x0d><> ) {    # inline Cpanel::C_StdLib::isspace
            $offset++;
        }

        $offset++;
    }

    $arg = substr( $line, $start_offset, $offset - $start_offset );
    $arg =~ s<\\([ \t])><$1>g if $arg =~ tr{ \t}{};

    if ( $offset < length $line ) {

        #The last character of the $arg here is either a quote
        #or a space. In either case, we need to be rid of it.
        #substr( $arg, -1 ) = q<>;

        $offset++;
    }

    die "No argument found at offset $start_offset of “$line”!" if $start_offset eq $offset;

    return ( $offset, $arg );
}

1;
