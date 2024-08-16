package Cpanel::Backup::Restore::Filter;

# cpanel - Cpanel/Backup/Restore/Filter.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

################################################################################

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Backup::Restore::Filter - Tools for filtering out acceptable errors from tar.

=head1 SYNOPSIS

    use Cpanel::Backup::Restore::Filter;

     my $stderr_ar = Cpanel::Backup::Restore::Filter::filter_stderr( \@stderr );

=head2 filter_stderr

Filters string of STDERR output for known false errors

=over 2

=item Input

=back

=over 3

=item stderr (required)     - The array reference pointing to the STDERR output

=back

=over 3

=item overwrite (required)  - Boolean indicating if overwrite was requested or not

=back

=over 2

=item Output

    Returns the (possibly) modified arrayref

=back

=cut

sub filter_stderr {
    my ( $stderr_ar_ref, $overwrite ) = @_;
    my @remaining_errors;
    foreach my $line ( @{$stderr_ar_ref} ) {

        # filter out common messages from tar that are not considered fatal. Note that this must be revisted once directories are added
        next if !defined($line);    # Skip empty lines/elements in array
        chomp($line);

        # If we get a file exists error with overwrite enabled, that indicates it is chasttr +i or something similar, so we want to keep it
        if ( defined $overwrite and $overwrite == 0 ) {
            $line =~ s/^.*\/bin\/.{0,1}tar\:.*\s+Cannot\sopen\:\sFile\sexists//g;
        }
        $line =~ s/^.*\/bin\/.{0,1}tar\:.*\s+Cannot create symlink to.*\:\sFile\sexists//g;
        $line =~ s/^.*\/bin\/.{0,1}tar\:\s+Removing\sleading.*names$//g;
        $line =~ s/^.*Exiting with failure status due to previous errors.*$//g;
        $line =~ s/.*tar_writer_child_pid exited prematurely.*//g;
        if ($line) {
            push( @remaining_errors, $line );
        }
    }
    return ( \@remaining_errors );
}

1;
