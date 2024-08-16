package Cpanel::Patch;

# cpanel - Cpanel/Patch.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Binaries        ();
use Cwd                     ();
use Cpanel::Logger          ();
use Cpanel::SafeRun::Errors ();

my $logger;

sub patch {
    my ( $data, $diff, $op_ref ) = @_;

    if ( !$op_ref->{'maxoffset'} ) {
        $op_ref->{'maxoffset'} = 0;
    }
    else {
        $op_ref->{'maxoffset'} = int $op_ref->{'maxoffset'};
    }

    if ( !$op_ref->{'verbose'} ) {
        $op_ref->{'verbose'} = 0;
    }
    else {
        $op_ref->{'verbose'} = 1;
    }

    my @DATA = split( /^/m, $data );
    my @DIFF = split( /^/m, $diff );
    my %HUNKS;
    my $err_count = 0;
    my $numhunks  = 0;
    foreach my $diff_line (@DIFF) {
        if ( $diff_line =~ m/^\@{2}\s+-(\d+),(\d+)/ ) {
            $numhunks++;
            $HUNKS{$numhunks}{'START'}  = int( $1 - 1 );
            $HUNKS{$numhunks}{'LENGTH'} = $2;
            $HUNKS{$numhunks}{'END'}    = $HUNKS{$numhunks}{'START'} + $HUNKS{$numhunks}{'LENGTH'};
            if ( $op_ref->{'maxoffset'} ) {
                $HUNKS{$numhunks}{'START'} -= $op_ref->{'maxoffset'};
                $HUNKS{$numhunks}{'END'}   += $op_ref->{'maxoffset'};
                if ( $HUNKS{$numhunks}{'START'} < 0 )           { $HUNKS{$numhunks}{'START'} = 0; }
                if ( $HUNKS{$numhunks}{'END'} > scalar(@DATA) ) { $HUNKS{$numhunks}{'END'}   = scalar(@DATA); }
            }
        }
        elsif ( defined( $HUNKS{$numhunks}{'START'} ) ) {
            if ( !defined( $HUNKS{$numhunks}{'HEADER_END_POS'} ) && $diff_line =~ m/^([\-\+])/ ) {
                $HUNKS{$numhunks}{'HEADER_END_POS'} = scalar( @{ $HUNKS{$numhunks}{'CONTENT'} } );
                $HUNKS{$numhunks}{'HEADER_LEN'}     = scalar( @{ $HUNKS{$numhunks}{'CONTENT'} } );
            }
            if ( defined( $HUNKS{$numhunks}{'HEADER_END_POS'} ) && !defined( $HUNKS{$numhunks}{'FIRST_OP_END_POS'} ) && $diff_line !~ m/^[\-\+]/ ) {
                $HUNKS{$numhunks}{'FIRST_OP_END_POS'} = scalar( @{ $HUNKS{$numhunks}{'CONTENT'} } );
                $HUNKS{$numhunks}{'FIRST_OP_LEN'}     = $HUNKS{$numhunks}{'FIRST_OP_END_POS'} - $HUNKS{$numhunks}{'HEADER_END_POS'};
            }
            push @{ $HUNKS{$numhunks}{'CONTENT'} }, $diff_line;
        }
    }

  HUNK:
    foreach my $hunk ( sort { $a <=> $b } keys %HUNKS ) {
        next if ( !$HUNKS{$hunk}{'START'} );    # Skip invalid '0' hunk

        for ( my $startpt = $HUNKS{$hunk}{'START'}; $startpt <= $HUNKS{$hunk}{'END'}; $startpt++ ) {
            if ( _lmatch( \@DATA, $HUNKS{$hunk}{'CONTENT'}, $startpt, 0, $HUNKS{$hunk}{'HEADER_END_POS'}, $op_ref ) ) {
                if ( $op_ref->{'verbose'} ) {
                    $logger->info("Started Patching at line $startpt.");
                }
                my $firstopmatch = _lmatch( \@DATA, $HUNKS{$hunk}{'CONTENT'}, $HUNKS{$hunk}{'HEADER_END_POS'} + $startpt, $HUNKS{$hunk}{'HEADER_LEN'}, $HUNKS{$hunk}{'FIRST_OP_LEN'} - 1, $op_ref );
                my $firstop      = substr( ${ $HUNKS{$hunk}{'CONTENT'} }[ $HUNKS{$hunk}{'HEADER_END_POS'} ], 0, 1 );
                if ( ( $firstop eq '-' && !$firstopmatch ) || ( $firstop eq '+' && $firstopmatch ) ) {
                    if ( $op_ref->{'verbose'} ) {
                        $logger->info("Hunk #${hunk} already applied!");
                        $err_count++;
                    }
                    next HUNK;
                }
                splice( @{ $HUNKS{$hunk}{'CONTENT'} }, 0, $HUNKS{$hunk}{'HEADER_END_POS'} );
                my $patchline    = 0;
                my $patchopstart = $startpt + $HUNKS{$hunk}{'HEADER_LEN'};
                foreach my $content_line ( @{ $HUNKS{$hunk}{'CONTENT'} } ) {
                    my $op         = substr( $content_line, 0, 1 );
                    my $patch_data = substr( $content_line, 1 );
                    if ( $op eq '+' ) {
                        splice @DATA, ( $patchopstart + $patchline ), 0, $patch_data;
                    }
                    elsif ( $op eq '-' ) {
                        splice @DATA, ( $patchopstart + $patchline ), 1;
                        $patchline--;
                    }
                    $patchline++;
                }
                if ( $op_ref->{'verbose'} ) {
                    $logger->info("Hunk #${hunk} succeeded!");
                }
                next HUNK;
            }
        }
    }

    wantarray ? return ( join( '', @DATA ), $err_count, $numhunks ) : return join( '', @DATA );
}

# Arguments:
#   ref to the source to match
#   stuff to match
#   where to start matching in the src
#   where to start matching in the match txt
#   how many elements to match
#   options
sub _lmatch {
    my ( $src_ref, $match_ref, $srcstart, $matchstart, $matchlength, $op_ref ) = @_;

    my $srctxt;
    my $testtxt;
    for ( my $i = 0; $i < $matchlength; $i++ ) {
        $srctxt  .= $$src_ref[ $i + $srcstart ];
        $testtxt .= substr( $$match_ref[ $i + $matchstart ], 1 );
    }
    if ( $op_ref->{'ignorespace'} ) {
        $srctxt  =~ s/\s+//g;
        $testtxt =~ s/\s+//g;
    }

    if ( $srctxt eq $testtxt ) {
        return 1;
    }
    return;
}

# Applies a git style patch directory to an extracted source tree
# Arguments:
#  directory containing patches (absolute path or relative path to the destination directory)
#  destination directory (optional, default current directory)
#  patch strip level (optional, default 1)
sub apply_patchset {
    my $src_dir     = shift;
    my $dest_dir    = shift;
    my $patch_level = shift || 1;

    $logger ||= Cpanel::Logger->new();

    my $git_bin = Cpanel::Binaries::path('git');
    unless ( -x $git_bin ) {
        $logger->warn("Could not find git binary");
        return;
    }

    my $start_dir;
    if ( defined $dest_dir ) {
        $start_dir = Cwd::getcwd();
        unless ( chdir($dest_dir) ) {
            $logger->warn("Could not change to $start_dir to begin patching: $!");
            return;
        }
    }

    my @args = ( qw/--no-index -p/, $patch_level );

    my $directory = Cpanel::SafeRun::Errors::saferunallerrors( $git_bin, 'rev-parse', '--show-prefix' );
    unless ($?) {
        chomp $directory;
        push @args, '--directory', $directory;
    }

    if ( opendir my $src_dh, $src_dir ) {
        my @patches = sort readdir($src_dh);
        my $applied = 0;
        foreach my $patch (@patches) {
            next unless ( $patch =~ /\.(?:patch|diff)$/ );
            my $output = Cpanel::SafeRun::Errors::saferunallerrors( $git_bin, 'apply', @args, $src_dir . '/' . $patch );
            chomp $output;
            if ($?) {
                $logger->warn("Error applying patch '$patch'\n$output");
                chdir($start_dir) if defined $start_dir;
                return;
            }
            else {
                $logger->info("Applied patch '$patch'\n$output");
                $applied++;
            }
        }
        chdir($start_dir) if defined $start_dir;
        if ($applied) {
            $logger->info("Successfully applied $applied patches");
            return 1;
        }
        else {
            $logger->info('No patches were applied, because none were tried; not a problem');
            return 1;
        }
    }
    else {
        my $opendir_err = $!;
        chdir($start_dir) if defined $start_dir;
        $logger->info("Could not open patch source directory '$src_dir' for reading; not a problem, I will just assume there are no patches that need applying; opendir error was: $opendir_err");
        return 1;
    }
}

1;
