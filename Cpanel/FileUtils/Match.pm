package Cpanel::FileUtils::Match;

# cpanel - Cpanel/FileUtils/Match.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::FileUtils::Match - Match files in a directory

=head1 SYNOPSIS

    use Cpanel::FileUtils::Match ();

    my %trailers = ('domain.tld' => 1, 'otherdomain.tld' => 1);
    my $list_files = Cpanel::FileUtils::Match::get_files_matching_trailers( "$Cpanel::ConfigFiles::MAILMAN_ROOT/archives/public",  '_', \%trailers ),

    my $list_files = Cpanel::FileUtils::Match::get_matching_files( "$Cpanel::ConfigFiles::MAILMAN_ROOT/lists", "_(?:$dns_list)" . '$' );

=cut

use constant _ENOENT => 2;

sub get_matching_files {
    my ( $dir, $regex ) = @_;
    my $compiled_regex;
    eval { $compiled_regex = qr/$regex/; };
    if ( !$compiled_regex ) {
        Cpanel::Debug::log_warn("Failed to compile regex “$regex”: $@");
        return;
    }

    my @filenames;

    if ( opendir( my $dir_h, $dir ) ) {

        # Quoted eval allowes m//o on both regexes
        @filenames = eval q{map { $_ =~ m{$compiled_regex}o && $_ ne '..' && $_ ne '.' ? "$dir/$_" : () } readdir($dir_h)};    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)

        # closedir($dir_h); will happen when the sub is left and $dir_fh falls out of scope
    }

    # do not warn when directory doesn't exist
    elsif ( $! != _ENOENT() ) {
        my $err = $!;
        require Cpanel::Debug;
        Cpanel::Debug::log_warn("Failed to open directory “$dir”: $err");
    }

    return \@filenames;
}

=head2 get_files_matching_trailers($dir, $separator, $trailers_hr)

Fetch a list of filenames in a directory that match a set of
trailers (in hash format). (See the SYNOPSIS for an example.)

=over 2

=item Input

=over 3

=item $dir C<SCALAR>

    The directory to look in.

=item $separator C<SCALAR>

    The separator to split the filenames on
    to look for the trailers

=item $trailers_hr C<HASHREF>

    A hashref of trailers with the value
    being true.

=back

=item Output

Returns an arrayref of matched filenames.

=back

=cut

sub get_files_matching_trailers {
    my ( $dir, $separator, $trailers_hr ) = @_;

    my @filenames;

    if ( opendir( my $dir_h, $dir ) ) {
        delete @{$trailers_hr}{ '.', '..' };

        my $separator_length = length $separator;

        @filenames = map { $trailers_hr->{ substr( $_, rindex( $_, $separator ) + $separator_length ) } ? "$dir/$_" : () } readdir($dir_h);
    }
    elsif ( $! != _ENOENT() ) {
        my $err = $!;
        require Cpanel::Debug;
        Cpanel::Debug::log_warn("Failed to open directory “$dir”: $err");
    }

    return \@filenames;
}

1;
