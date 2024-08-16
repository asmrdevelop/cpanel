package Cpanel::SafeDir::MK;

# cpanel - Cpanel/SafeDir/MK.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# This module is included in queueprocd; please do not add
# any new use statements here as it will bloat queueprocd
use Cpanel::Debug ();

my $DEFAULT_PERMISSIONS = 0755;

=head1 MODULE

C<Cpanel::SafeDir::MK>

=head1 DESCRIPTION

C<Cpanel::SafeDir::MK> provides helper methods that work like C<mkdir -p>.

=head1 FUNCTIONS

=head2 safemkdir_or_die(DIR, MODE, CREATED)

=head3 ARGUMENTS

=over

=item DIR - string

The path to the directory that you want to create. If any parts of the parent folders are
missing along the directory path, those will also be created.

=item MODE - string

Optional. The file system mode to set on the directory. If not passed, it defaults to '0755'.

=item CREATED - array ref

Optional. If passed, it will be an array of the created directories.

=back

=head3 RETURNS

True value if the directory exists or was successfully created and is accessible.

=head3 THROWS

=over

=item When the system failed to create one or more directories or failed to set the directory's permissions.

=back

=head3 EXAMPLES

    use Cpanel::SafeDir::MK ();

    # create a dir with the default permissions
    Cpanel::SafeDir::MK::safemkdir_or_die('/home/cptest/dir1');

    # create a dir with the custom permissions
    Cpanel::SafeDir::MK::safemkdir_or_die('/home/cptest/dir2', '0700');

    # create a dir with the custom permissions
    my $created = [];
    Cpanel::SafeDir::MK::safemkdir_or_die('/home/cptest/dira/dirb/dirc', '0755', $created);
    foreach my $dir (@$created) {
       print "Created: $dir\n";
    }

=cut

sub safemkdir_or_die {
    my ( $dir, $mode, $created ) = @_;
    my $ok = safemkdir( $dir, $mode, $created );
    if ( !$ok ) {
        my $error = $!;
        require Cpanel::Exception;
        die Cpanel::Exception::create(
            'IO::DirectoryCreateError',
            [
                path  => $dir,
                error => $error,
            ]
        );
    }
    return $ok;
}

=head2 safemkdir(DIR, MODE, ERRORS, CREATED)

=head3 ARGUMENTS

=over

=item DIR - string

Path to the directory you want to create. If any parts parent folders are
missing along the path those will also be created.

=item MODE - string

Optional. File system mode to set on the directory. If not passed it will default to '0755'.

=item ERRORS - unused

Legacy parameter that is not used anymore, but preserved so callers do not break.

=item CREATED - array ref

Optional, if passed, it will be filled with the list of directories created.

=back

=head3 RETURNS

True value if the directory exists or was successfully created and is accessible. Returns a false value otherwise.

=head3 EXAMPLES

    use Cpanel::SafeDir::MK ();

    # create a dir with the default permissions
    if (Cpanel::SafeDir::MK::safemkdir('/home/cptest/dir1')) {
        # do something with the directory.
    }

    # create a dir with the custom permissions
    if (Cpanel::SafeDir::MK::safemkdir_or_die('/home/cptest/dir2', '0700')) {
        # do something with the directory.
    }

    # create a dir with the custom permissions
    my $created = [];
    if (Cpanel::SafeDir::MK::safemkdir_or_die('/home/cptest/dira/dirb/dirc', '0755', undef, $created)) {
        foreach my $dir (@$created) {
           print "Created: $dir\n";
        }
        # do something with the directory.
    };

=cut

sub safemkdir {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $dir, $mode, $errors, $created ) = @_;

    # Set mode if not properly defined.  Acceptable inputs include a number or
    # an octal string starting with 0.
    if ( defined $mode ) {
        if ( $mode eq '' ) {
            $mode = undef;
        }
        elsif ( index( $mode, '0' ) == 0 ) {
            if ( length $mode < 3 || $mode =~ tr{0-7}{}c || !defined oct $mode ) {
                $mode = $DEFAULT_PERMISSIONS;
            }
            else {
                $mode = oct($mode);
            }
        }
        elsif ( $mode =~ tr{0-9}{}c ) {
            $mode = $DEFAULT_PERMISSIONS;
        }
    }
    $dir =~ tr{/}{}s;

    my $default = '';
    if ( index( $dir, '/' ) == 0 ) {
        $default = '/';
    }
    elsif ( $dir eq '.' || $dir eq './' ) {
        if ( !-l $dir && defined $mode ) {
            return chmod $mode, $dir;
        }
        return 1;
    }
    else {
        substr( $dir, 0, 2, '' ) if index( $dir, './' ) == 0;
    }

    # We may be able to use Cpanel::Validate::FilesystemPath in the future
    # here once we clean this up a bit more
    if ( _has_dot_dot($dir) ) {
        Cpanel::Debug::log_warn("Possible improper directory $dir specified");
        my @dir_parts = split m{/}, $dir;
        my @good_parts;
        my $first;
        foreach my $part (@dir_parts) {
            next if ( !defined $part || $part eq '' );
            next if $part eq '.';
            if ( $part eq '..' ) {
                if ( !$first || !@good_parts ) {
                    Cpanel::Debug::log_warn("Will not proceed above first directory part $first");
                    return 0;
                }
                if ( $first eq $good_parts[$#good_parts] ) {
                    undef $first;
                }
                pop @good_parts;
                next;
            }
            elsif ( $part !~ tr{.}{}c ) {
                Cpanel::Debug::log_warn("Total stupidity found in directory $dir");
                return 0;
            }
            push @good_parts, $part;
            if ( !$first ) { $first = $part }
        }
        $dir = $default . join '/', @good_parts;
        if ( !$dir ) {
            Cpanel::Debug::log_warn("Could not validate given directory");
            return;
        }
        Cpanel::Debug::log_warn("Improper directory updated to $dir");
    }

    if ( -d $dir ) {
        if ( !-l $dir && defined $mode ) {
            return chmod $mode, $dir;
        }
        return 1;
    }
    elsif ( -e _ ) {
        Cpanel::Debug::log_warn("$dir was expected to be a directory!");
        require Errno;
        $! = Errno::ENOTDIR();    ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- for legacy reasons
        return 0;
    }

    my @dir_parts = split m{/}, $dir;

    # Assume that there will be no more than 100 nested directories
    if ( scalar @dir_parts > 100 ) {
        Cpanel::Debug::log_warn("Encountered excessive directory length. This should never happen.");
        return 0;
    }
    my $returnvalue;
    foreach my $i ( 0 .. $#dir_parts ) {
        my $newdir = join( '/', @dir_parts[ 0 .. $i ] );
        next if $newdir eq '';
        my $is_dir = -d $newdir;
        my $exists = -e _;

        if ( !$exists ) {
            my $local_mode = defined $mode ? $mode : $DEFAULT_PERMISSIONS;
            if ( mkdir( $newdir, $local_mode ) ) {
                push @{$created}, $newdir if $created;
                $returnvalue++;
            }
            else {
                Cpanel::Debug::log_warn("mkdir $newdir failed: $!");
                return;
            }
        }
        elsif ( !$is_dir ) {
            Cpanel::Debug::log_warn("Encountered non-directory $newdir in path of $dir: $!");
            require Errno;
            $! = Errno::ENOTDIR();    ## no critic qw(Variables::RequireLocalizedPunctuationVars) -- for legacy reasons
            last;
        }
    }
    return $returnvalue;
}

# Tested directly because we’ve gotten this wrong previously,
# but also because this isn’t logic we really want to apply anywhere else.
# It *just* verifies that there are no “..” nodes in the path.
# It used to be: m/(?:^|\/)\.\.(?:\/|$)/
#
sub _has_dot_dot {    ## no critic qw(RequireArgUnpacking)
    return 1 if $_[0] eq '..';
    return 1 if -1 != index( $_[0], '/../' );
    return 1 if 0 == index( $_[0], '../' );
    return 1 if ( length( $_[0] ) - 3 ) == rindex( $_[0], '/..' );

    return 0;
}

1;
