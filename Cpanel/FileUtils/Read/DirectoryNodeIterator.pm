package Cpanel::FileUtils::Read::DirectoryNodeIterator;

# cpanel - Cpanel/FileUtils/Read/DirectoryNodeIterator.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: There's probably no gain from using this module directly; it
#basically exists as a "helper" class to Cpanel::FileUtils::Read.
#----------------------------------------------------------------------

use strict;
use warnings;

use Try::Tiny;

use base qw(
  Cpanel::FileUtils::Read::IteratorBase
);

sub _run {
    my ($self) = @_;

    my $fh = $self->{'_fh'};

    my $todo_cr         = $self->{'_todo_cr'};
    my $iteration_index = 0;

    $self->{'_iteration_index_sr'} = \$iteration_index;

    $self->_run_try_catch(
        sub {
            local $_;

            while ( $_ = readdir $fh ) {
                next if $_ eq '.' || $_ eq '..';

                local $!;
                $todo_cr->($self);
                $iteration_index++;
            }

            #Perl, for many years, set $! to EBADF at the end of iterating through
            #a directory with readdir(), which effectively makes $! useless since
            #successful iterations will show spurious failures.
            #This is fixed in 5.20.
            #
            #One-liner to see the bug:
            #perl -e'opendir my $d, "."; 1 while readdir($d); print $!'
            #
            #cf. https://rt.perl.org/Public/Bug/Display.html?id=118651
            #https://github.com/Perl/perl5/commit/ee71f1d151acd0a4c10ebcec28f0798178529847
            #
            #In order to prevent creating spurious exceptions here, we simply
            #unset the error if it’s the condition that the above RT fixed.
            #
            if ( $! && $^V lt v5.20 ) {
                require Errno;
                if ( $! == Errno::EBADF() ) {
                    $! = 0;    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
                }
            }
        }
    );

    return 1;
}

sub _READ_ERROR_EXCEPTION_CLASS {
    return 'IO::DirectoryReadError';
}

1;
