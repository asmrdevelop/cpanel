package Cpanel::Locale::Utils::TPDS;

# cpanel - Cpanel/Locale/Utils/TPDS.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

my $delim = '%%%%';

sub get_delim {
    return $delim;
}

sub get_delim_line {
    my ( $file, $line, $offset, $quote_before, $quote_after ) = @_;

    my $str = get_delim();
    if ($file) {
        $str .= " file $file";
        $str .= " line $line"     if defined $line;
        $str .= " offset $offset" if defined $offset;
        $str .= " $delim";
    }
    if ($quote_before) {
        $str .= " 0x" . unpack 'H*', $quote_before;
        $str .= " 0x" . unpack 'H*', ( $quote_after // '' );
        $str .= " $delim";
    }
    return "$str\n";
}

sub get_phrase_line {
    my ($line) = @_;
    return normalize_parsed_phrase($line) . "\n";
}

sub output_phrase {
    my ( $phrase, %extra ) = @_;
    return if !defined $phrase || $phrase eq '';
    print get_phrase_line($phrase);
    print get_delim_line( @extra{qw(file line offset quote_before quote_after)} );
    return;
}

sub get_phrases_as_output_string {
    my @phrases = @_;

    # same as a script that calls output_phrase($phrase) for each one (if any)
    return '' if !@phrases;
    return join( get_delim_line(), map { get_phrase_line($_) } @phrases ) . get_delim_line();
}

sub get_phrases_from_output_string {
    my ($str) = @_;
    return if !defined $str || $str eq '';

    return map {
        my $line = normalize_parsed_phrase($_);
        $line eq '' ? () : $line;
    } split( m/\Q$delim\E(?:.+\Q$delim\E)?\n?/m, $str );
}

sub handle_phrases_from_script_output {
    my ( $script, $phrase_handler ) = @_;

    if ( !-x $script ) {
        warn "$script is not executable";
        return;
    }

    require Cpanel::SafeRun::Object;
    require Cpanel::IOCallbackWriteLine;

    my $linenum              = 0;
    my $aggregate            = '';
    my $aggregate_start_line = 0;
    my %extra;

    my $out_fh = Cpanel::IOCallbackWriteLine->new(
        sub {
            my ($line) = @_;
            $linenum++;

            if ( $line =~ m/^\Q$delim\E(?: file (?<file>.*?)(?: line (?<line>[0-9]+))?(?: offset (?<offset>[0-9]+))? \Q$delim\E)?(?: 0x(?<quote_before>(?:[0-9a-f]{2})*) 0x(?<quote_after>(?:[0-9a-f]{2})*) \Q$delim\E)?$/m ) {
                %extra               = %+;
                $extra{quote_before} = pack 'H*', $extra{quote_before} if $extra{quote_after};
                $extra{quote_after}  = pack 'H*', $extra{quote_after}  if $extra{quote_after};
                my $clean = normalize_parsed_phrase($aggregate);
                $phrase_handler->( $clean, $aggregate_start_line, \%extra );
                $aggregate            = '';
                $aggregate_start_line = $linenum + 1;
            }
            else {
                $aggregate_start_line = $linenum if $aggregate eq '';
                $aggregate .= $line;
            }
        }
    );
    my $run = Cpanel::SafeRun::Object->new(
        program => $script,
        args    => [],
        stdout  => $out_fh,
        stderr  => \*STDERR,
    );

    # Required to flush incomplete lines.
    undef $out_fh;

    # in case there was no trailing delim line and we didn't die:
    if ( $aggregate ne '' && $run->CHILD_ERROR() == 0 ) {
        my $clean = normalize_parsed_phrase($aggregate);
        $phrase_handler->( $clean, $aggregate_start_line, \%extra );
    }

    die "$script did not exit cleanly" if $run->CHILD_ERROR() != 0;
    return;
}

sub normalize_parsed_phrase {
    my ($phrase) = @_;
    $phrase =~ s/\n$//;    # instead of Cpanel::StringFunc::Trim::ws_trim(), this will preserve any leading/trailing WS (for the filters to catch and report later)
    return $phrase;
}

1;

__END__

=head1 Translatable Phrase Dumper Scripts (aka TPDS)

This module helps implement the TPDS interface described at L<http://fogbugz.cpanel.net/default.asp?W1528>.
