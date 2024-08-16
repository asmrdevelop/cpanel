package Cpanel::CSVImport::Process;

# cpanel - Cpanel/CSVImport/Process.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule      ();
use Cpanel::SafeRun::Simple ();

=head1 NAME

Cpanel::CSVImport::Process

=head1 DESCRIPTION

Parses CSV/XLS files and returns the stored data.

=head1 SYNOPSIS

my $data = Cpanel::CSVImport::Process::process( "/tmp/file.csv", 1, "comma" );

=head1 FUNCTIONS

=head2 process($filename, $first_line_is_header, $delimeter)

Parses CSV/XLS files and returns the stored data.

  - filename - File name to parse. (string)
  - first_line_is_header - First line contains header data. (boolean)
  - delimeter - Column delimeter. (string)

The delimiter argument will take the following options:

  - space
  - semi
  - tab
  - comma

Alternatively, a single character may be passed, which will be used as the delimeter.

=cut

sub process {
    my ( $file, $first_line_is_header, $delim ) = @_;

    my $type = Cpanel::SafeRun::Simple::saferun( 'file', $file );

    # Remove the filename from the file type output so any
    # contents of the path do not get confused for the file type
    $type =~ s/$file//;

    my $dataref = { 'data' => [], 'header' => [] };

    if ( $type =~ m/excel|office|microso|composite/i ) {
        Cpanel::LoadModule::load_perl_module('Spreadsheet::ParseExcel');
        my $excel = Spreadsheet::ParseExcel::Workbook->Parse($file);

        foreach my $sheet ( @{ $excel->{'Worksheet'} } ) {
            $sheet->{'MaxRow'} ||= $sheet->{'MinRow'};
            my $line = 0;
            foreach my $row ( $sheet->{'MinRow'} .. $sheet->{'MaxRow'} ) {
                $sheet->{'MaxCol'} ||= $sheet->{'MinCol'};
                my @columns;
                foreach my $col ( $sheet->{'MinCol'} .. $sheet->{'MaxCol'} ) {
                    my $cell = $sheet->{'Cells'}[$row][$col];
                    push @columns, $cell->{'Val'};
                }
                next if _isblank( \@columns );

                # TODO: Replace the following line with a real solution.
                # Spreadsheet::ParseExcel fakes UTF-16 by sticking in leading nul characters.
                # The string format is not recognized correctly, so we need to undo S::PE's
                # hack to be able to read the files correctly. This could break if there are
                # real UTF characters greater than the ASCII set.
                @columns = map { my $c = $_; $c =~ tr/\0//d; $c } @columns;
                $line++;
                if ( $line == 1 && $first_line_is_header ) {
                    $dataref->{'header'} = \@columns;
                }
                else {
                    push @{ $dataref->{'data'} }, \@columns;
                }
                $dataref->{'columns'} = ( ( defined( $dataref->{'columns'} ) && ( $dataref->{'columns'} > scalar @columns ) ) ? $dataref->{'columns'} : scalar @columns );
            }
            last;
        }
    }
    else {
        Cpanel::LoadModule::load_perl_module('Text::CSV');
        if ( $delim =~ m/space/i ) {
            $delim = ' ';
        }
        elsif ( $delim =~ m/semi/i ) {
            $delim = ';';
        }
        elsif ( $delim =~ m/tab/i ) {
            $delim = "\t";
        }
        elsif ( $delim =~ m/comma/i ) {
            $delim = ',';
        }
        elsif ($delim) {
            $delim = substr( $delim, 0, 1 );
        }
        else {
            $delim = ',';
        }

        my $csv = Text::CSV->new( { 'sep_char' => $delim } );

        my $line = 0;
        if ( open my $csv_fh, '<', $file ) {
            while ( readline($csv_fh) ) {
                $csv->parse($_);
                my @columns = $csv->fields();
                next if _isblank( \@columns );
                $line++;

                if ( $line == 1 && $first_line_is_header ) {
                    $dataref->{'header'} = \@columns;
                }
                else {
                    push @{ $dataref->{'data'} }, \@columns;
                }
                $dataref->{'columns'} = ( ( defined( $dataref->{'columns'} ) && ( $dataref->{'columns'} > scalar @columns ) ) ? $dataref->{'columns'} : scalar @columns );
            }
            close $csv_fh;
        }
    }

    return $dataref;
}

sub _isblank {
    my $colref = shift;
    return 1 if !ref $colref;

    foreach my $val ( @{$colref} ) {
        return 0 if $val;
    }
    return 1;
}

1;
