package Cpanel::FileUtils::Lines;

# cpanel - Cpanel/FileUtils/Lines.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use Cpanel::Debug ();
use IO::SigGuard  ();

use constant _ENOENT => 2;

our $VERSION = '1.0';

my $MAX_LINE_SIZE = 32768;

sub get_file_lines {
    my $cfgfile     = shift;
    my $line_number = shift;
    return if ( !$line_number || $line_number !~ m/^\d+$/ );

    my $numpadding = 7;
    my %ret;
    if ( open( my $cfg_fh, '<', $cfgfile ) ) {
        my $linecounter = 0;
        while ( readline($cfg_fh) ) {
            $linecounter++;
            if ( $linecounter < $line_number && $linecounter > ( $line_number - $numpadding ) ) {
                push @{ $ret{'previouslines'} }, { 'line' => $linecounter, 'data' => $_ };
            }
            elsif ( $linecounter > $line_number && $linecounter < ( $line_number + $numpadding ) ) {
                push @{ $ret{'afterlines'} }, { 'line' => $linecounter, 'data' => $_ };
            }
            elsif ( $linecounter == $line_number ) {
                push @{ $ret{'lines'} }, { 'line' => $linecounter, 'data' => $_ };
            }
            elsif ( $linecounter > ( $line_number + $numpadding ) ) {
                last;
            }
        }
        close $cfg_fh;
    }
    return \%ret;
}

sub get_last_lines {
    my $cfgfile = shift;
    my $number  = shift;
    if ( !$number || $number !~ m/^\d+$/ ) {
        $number = 10;
    }
    my @lines;

    if ( open( my $cfg_fh, '<', $cfgfile ) ) {
        my $size = ( stat($cfg_fh) )[7];
        if ( $size > ( $MAX_LINE_SIZE * $number ) ) {

            # If we process a giant mysql error log we previously
            # loaded the entire thing.  Now we just seek back X * MAX_LINE_SIZE
            # and start there as this took almost 2 minutes every time mysql
            # was being restarted
            seek( $cfg_fh, $size - ( $MAX_LINE_SIZE * $number ), 0 );
        }
        my $linecounter = 0;
        while ( my $line = readline($cfg_fh) ) {
            chomp $line;
            if ( $linecounter >= $number ) {
                shift @lines;
            }
            push @lines, $line;
            $linecounter++;
        }
        close $cfg_fh;
    }
    else {
        Cpanel::Debug::log_warn("Unable to open $cfgfile: $!");
    }
    return wantarray ? @lines : \@lines;
}

sub has_txt_in_file {
    my ( $file, $txt ) = @_;

    my $regex;
    eval { $regex = qr($txt); };
    if ($@) {
        Cpanel::Debug::log_warn('Invalid regex');
        return;
    }

    my $fh;
    if ( open $fh, '<', $file ) {
        while ( my $line = readline $fh ) {
            if ( $line =~ $regex ) {
                close $fh;
                return 1;
            }
        }

        close $fh;
    }

    return;
}

sub appendline {
    my ( $filename, $line ) = @_;
    my $fh;

    if ( open my $fh, '>>:stdio', $filename ) {

        # Must bypass perl i/o to ensure this happens in a single
        # write
        IO::SigGuard::syswrite( $fh, $line . "\n" ) or do {
            warn "write($filename): $!";
        };

        close $fh;
        return 1;
    }
    else {
        warn "open($filename): $!" if $! != _ENOENT();
    }

    return;
}

1;
