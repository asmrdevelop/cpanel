package Cpanel::SafeSync::UserDir;

# cpanel - Cpanel/SafeSync/UserDir.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Proc::FastSpawn            ();
use Cpanel::Chdir              ();
use Cpanel::ForkAsync          ();
use Cpanel::Tar                ();
use Cpanel::ConfigFiles        ();
use Cpanel::TimeHiRes          ();
use Cpanel::AccessIds::SetUids ();
use Cpanel::FHUtils::Autoflush ();

our $ALLOW_FASTSPAWN = 1;    # for testing

sub restore_to_userdir {    ## no critic(Subroutines::ProhibitExcessComplexity)
                            # We based this on sync_to_userdir, but due to the existing complexity and critical nature of this code,
                            # we decided it better at this point to duplicate the code and modify it rather than actively developing in
                            # a space that is already extremely fragile
    my %OPTS = @_;

    my $tarcfg = Cpanel::Tar::load_tarcfg();
    if ( !exists $OPTS{'wildcards_match_slash'} ) {
        $OPTS{'wildcards_match_slash'} = 1;
    }

    my @extra_tar_args;
    if ( !$OPTS{'wildcards_match_slash'} && $tarcfg->{'no_wildcards_match_slash'} ) {
        push @extra_tar_args, '--no-wildcards-match-slash';
    }
    if ( defined $OPTS{'exclude'} ) {
        if ( exists $OPTS{'anchored_excludes'} && $OPTS{'anchored_excludes'} == 1 ) {
            push @extra_tar_args, '--anchored';
        }
        my $excludes = ref $OPTS{'exclude'} eq 'ARRAY' ? $OPTS{'exclude'} : [ $OPTS{'exclude'} ];
        foreach my $exclude (@$excludes) {
            push @extra_tar_args, "--exclude=$exclude";
        }
    }

    my $tbpath = $OPTS{'tarballpath'};
    my $source = $OPTS{'source'};

    # If using tarballpath in the args, we know this is for restoring a file or dir from a tarball, so source is used as a relative path inside the tarball
    if ($tbpath) {
        return undef if !-f $tbpath;
        return undef if !$source;
    }
    else {
        return undef if !-e $source;
    }

    my $target = $OPTS{'target'};

    # Ensure we never overwrite /XXXX or /usr/local/cpanel
    # These are various safety checks to avoid blowing away
    # any directories that should never be synced to.
    my $target_with_trailing_slash = $target;
    $target_with_trailing_slash =~ s{/+$}{};
    $target_with_trailing_slash =~ s{/+}{/}g;    # collapse /// into /
    if ( ( $target_with_trailing_slash =~ tr{/}{} ) <= 1 ) {
        die "restore_to_userdir: Cannot sync to a top level directory: “$target”.";
    }
    elsif ( $target_with_trailing_slash eq $Cpanel::ConfigFiles::CPANEL_ROOT ) {
        die "restore_to_userdir: Cannot sync to “$Cpanel::ConfigFiles::CPANEL_ROOT”.";
    }

    # Case 131613, the fix (--recursive-unlink required the explicitly listing
    # the files to transfer on the tar reader command line.   This caused
    # problems when there were no files in the source directory.

    my ( $base_dir, $source_path ) = return_base_dir($source);
    my $strip = 0;

    if ( !$tbpath ) {
        lstat($source);
        if ( -d _ ) {    # scenario, restore a directory from incremental
            $source_path = $OPTS{'source'};
            $base_dir    = $OPTS{'base_dir'};
            $strip       = get_strip_length($base_dir);
        }
    }

    my @tar_reader_child_args = (
        '--create',
        '--file' => '-',
        @extra_tar_args,

        # Since we are not writing to a .tar file only a pipe that will untar
        # we can use --sparse
        # and  case 19266 (work around for win32 bug) is not relevant
        Cpanel::Tar::OPTIMIZATION_OPTIONS(),

        # For added safety we pass the --directory flag to tar as
        # we want to ensure that no DESTROY or other handler
        # can switch the directory out from under us as this seems
        # to be possible when run though cplint
        '--directory' => $base_dir,

        '--',
        $source_path
    );

    # If we are not reading from a tarball, we do not want to unquote file names.
    unshift @tar_reader_child_args, '--no-unquote' if !$tbpath;

    # Do not ever remove this
    die "--directory is required for safety" if !grep( m/^--directory$/, @tar_reader_child_args );

    my @tar_writer_child_args;

    # If we are reading from a tarball, this process is reversed, so the writer needs to write to the file/dir
    if ($tbpath) {

        # TODO once we have backup type in the meta data we can do gzip_arg
        # correctly
        my $gzip_arg = '';
        if ( $tbpath =~ m/z$/ ) {
            $gzip_arg = '-z';
        }

        # confusing so here it is:
        # We want to overwrite or not but the flag in tar is
        # "--keep-old-files" or -k
        my $keep_files = '';
        if ( defined $OPTS{'overwrite'} && $OPTS{'overwrite'} == 0 ) {
            $keep_files = '-k';
        }

        @tar_writer_child_args = (
            '--extract',
            $gzip_arg,
            $keep_files,
            $tarcfg->{'no_same_owner'},
            '--preserve-permissions',
            '--no-wildcards',
            '--no-unquote',
            '--file' => '-',
            @extra_tar_args,

            # We use this to fix the path compared to what we pull from the user/homedir/ path of the backup
            '--strip=2',    # . $path_segments,

            # Since we are not writing to a .tar file only a pipe that will untar
            # we can use --sparse
            # and  case 19266 (work around for win32 bug) is not relevant
            Cpanel::Tar::OPTIMIZATION_OPTIONS(),

            # For added safety we pass the --directory flag to tar as
            # we want to ensure that no DESTROY or other handler
            # can switch the directory out from under us as this seems
            # to be possible when run though cplint
            '--directory' => $target,
            '--',
            $source
        );
    }
    else {
        # confusing so here it is:
        # We want to overwrite or not but the flag in tar is
        # "--keep-old-files" or -k
        my $keep_files = '';
        if ( defined $OPTS{'overwrite'} && $OPTS{'overwrite'} == 0 ) {
            $keep_files = '-k';
        }

        @tar_writer_child_args = (
            '--extract',
            $keep_files,
            $tarcfg->{'no_same_owner'},
            '--preserve-permissions',
            '--file' => '-',
            @extra_tar_args,
            '--strip=' . $strip,    # minimum of 5 for homedir directory, more for subdirs

            #
            # As was discovered in the midst of diagnosing case 49702, it is a good
            # idea to ensure that buffer sizes on both the tarball creating and
            # tarball extracting ends match.  Since GNU tar does not complain if the
            # data written to it is smaller than its read buffer, it is safe to make
            # it attempt to read block/buffer padding beyond the file size indicated
            # in the last header read.
            #
            # In other words, passing these options to the extracting tar process is
            # fine when /bin/cat is used to "produce" the tarball stream, but is
            # definitely mandatory when greater block sizes are written by the
            # archiving tar process; if the buffer sizes don't match, then the
            # archiving tar process will complain that not all of the data it wrote
            # was written, even if this data is nul padding.
            #
            Cpanel::Tar::OPTIMIZATION_OPTIONS(),

            # For added safety we pass the --directory flag to tar as
            # we want to ensure that no DESTROY or other handler
            # can switch the directory out from under us as this seems
            # to be possible when run though cplint
            '--directory' => $target,
        );
    }

    # Strip out empty elements from the array. The difference between having an empty element in the wrong place
    # and not is a real thing.         ⬐right there, causes all files to be restored rather than just one
    # "/bin/gtar", "--extract", "-z", "", "--no-same-owner", "--preserve-permissions", "--file", "-",

    @tar_writer_child_args = grep { $_ ne '' } @tar_writer_child_args;
    @tar_reader_child_args = grep { $_ ne '' } @tar_reader_child_args;

    # Do not ever remove this
    die "--directory is required for safety" if !grep( m/^--directory$/, @tar_writer_child_args );

    my $out_pipe;
    my $in_pipe;
    pipe( $out_pipe, $in_pipe ) or die "Failed to create pipe: $!";
    Cpanel::FHUtils::Autoflush::enable($out_pipe);
    Cpanel::FHUtils::Autoflush::enable($in_pipe);

    my $tar_reader_child_pid = _spawn_reader_child(
        'in_pipe'                  => $in_pipe,
        'tar_ball_path'            => ( $tbpath                || '' ),
        'source_setuid'            => ( $OPTS{'source_setuid'} || 0 ),
        'base_dir'                 => $base_dir,
        'tarcfg'                   => $tarcfg,
        'tar_reader_child_args_ar' => \@tar_reader_child_args,
    );

    # To get errors from child to parent of the fork
    my $reporter_pipe;
    my $reportee_pipe;
    pipe( $reporter_pipe, $reportee_pipe ) or die "Failed to create reporting pipe: $!";
    Cpanel::FHUtils::Autoflush::enable($reporter_pipe);
    Cpanel::FHUtils::Autoflush::enable($reportee_pipe);

    my @writer_errors;

    my $tar_writer_child_pid = Cpanel::ForkAsync::do_in_child(
        sub {
            if ( $OPTS{'setuid'} ) {
                Cpanel::AccessIds::SetUids::setuids( $OPTS{'setuid'}->[0], $OPTS{'setuid'}->[1] );
            }

            if ( -l $target ) {
                warn "Trying to write in to a symlink as if it were a directory: $target";
                push( @writer_errors, "Trying to write in to a symlink as if it were a directory: $target" );
                exit(1);
            }

            # Try to create the target path if does not exist
            if ( !-e $target ) {
                if ( !mkdir( $target, 0755 ) ) {
                    require File::Path;
                    File::Path::make_path($target);
                }
            }

            open( \*STDIN,  "<&=", $out_pipe )      or die "Failed to connect STDIN to the pipe: $!";
            open( \*STDOUT, '>&=', $reportee_pipe ) or die "Failed to connect STDOUT to the pipe: $!";
            open( \*STDERR, '>&=', $reportee_pipe ) or die "Failed to connect STDERR to the pipe: $!";

            chdir($target) or die "chdir($target): $!";

            # case 160525, 151613, 110645, remove public_html if it exists to allow for a
            # symlinked public_html.

            if ( $OPTS{'overwrite_public_html'} ) {
                if ( -l 'public_html' or -f _ ) {
                    unlink 'public_html';
                }
                elsif ( -e _ ) {
                    require File::Path;
                    File::Path::remove_tree('public_html');
                }
            }
            exec( $tarcfg->{'bin'}, @tar_writer_child_args ) or die "exec($tarcfg->{'bin'} @tar_writer_child_args): $!";
        }
    );

    close($out_pipe);
    close($reportee_pipe);

    @writer_errors = <$reporter_pipe>;

    close($reporter_pipe);

    waitpid( $tar_writer_child_pid, 0 );

    ###########################################################
    # Analyse error output and decide how to handle it
    ###########################################################

    my $overwrite = 0;
    if ( defined $OPTS{'overwrite'} && $OPTS{'overwrite'} == 1 ) {
        $overwrite = 1;
    }
    require Cpanel::Backup::Restore::Filter;
    my $writer_errors_ar = Cpanel::Backup::Restore::Filter::filter_stderr( \@writer_errors, $overwrite );
    if ( @{$writer_errors_ar} ) {
        warn( "The backup writing process returned errors while working with “$source”.\n" . "The arguments for the writing process were ( @tar_writer_child_args ).\nThe arguments for the reading prcoess were ( @tar_reader_child_args )\nErrors:\n" . "-" x 80 . "\n" . join( "\n", @{$writer_errors_ar} ) . "\n" . "-" x 80 . "\n" );
        kill 'KILL', $tar_reader_child_pid;
        waitpid( $tar_reader_child_pid, 0 );
        return undef;
    }

    if ( waitpid( $tar_reader_child_pid, 1 ) ) {
        if ( $? != 0 ) {
            my $signal = $? & 0x7f;
            my $status = $? >> 8;
            warn("tar_reader_child_pid exited prematurely (signal: $signal; status: $status) while working with target: $target, with arguments (@tar_reader_child_args)");
            return undef;
        }
    }

    if ( $tar_reader_child_pid && kill( 0, $tar_reader_child_pid ) > 0 ) {
        Cpanel::TimeHiRes::sleep(0.25);
        waitpid( $tar_reader_child_pid, 1 );
        if ( $tar_reader_child_pid && kill( 0, $tar_reader_child_pid ) > 0 ) {
            my $uid = $<;
            if ( $OPTS{'setuid'} ) {
                $uid = $OPTS{'setuid'}->[0];
            }
            my $user = ( getpwuid($uid) )[0];
            print STDERR "Unexpected termination.  The tar child process running as user ($user) was prematurely terminated.  The process may have been terminated by a process killer, or other event.\n";
            kill 'KILL', $tar_reader_child_pid;
            waitpid( $tar_reader_child_pid, 0 );
            if ( $? != 0 ) {
                warn("tar_reader_child_pid exited with unexpected signal while working with target: $target");
                return undef;
            }

        }
    }
    return 1;
}

sub return_base_dir {
    my ($path) = @_;
    my $cnt = my @breakdown = split( /\//, $path );
    $cnt--;
    my $file = pop @breakdown;
    return ( join( '/', @breakdown ) . '/', $file, $cnt );
}

#NOTE: All this returns is a boolean to indicate success/failure.
#TODO: Make it also indicate what the failure was.
#
# %OPTS are:
#
#   - source: The directory to read from.
#
#   - target: The directory where to extract everything.
#
#   - setuid: array ref to give to setuids() in writer tar process.
#
#   - source_setuid: Similar to “setuid” but for the reader tar process.
#
#   - wildcards_match_slash: 1 if nonexistent.
#       Controls tar --no-wildcards-match-slash (in inversion)
#
#   - include: array ref of relative paths for the reader to include.
#       Defaults to ['.'] (i.e., everything). Must not be empty.
#
#   - exclude: array ref of --exclude args to give to tar
#
#   - anchored_excludes: Controls tar --anchored.
#
#   - overwrite_public_html: Whether to pre-remove public_html.
#
sub sync_to_userdir {    ## no critic(Subroutines::ProhibitExcessComplexity)
    my %OPTS = @_;

    my $tarcfg = Cpanel::Tar::load_tarcfg();
    if ( !exists $OPTS{'wildcards_match_slash'} ) {
        $OPTS{'wildcards_match_slash'} = 1;
    }

    my @extra_tar_args;
    if ( !$OPTS{'wildcards_match_slash'} && $tarcfg->{'no_wildcards_match_slash'} ) {
        push @extra_tar_args, '--no-wildcards-match-slash';
    }
    if ( defined $OPTS{'exclude'} ) {
        if ( exists $OPTS{'anchored_excludes'} && $OPTS{'anchored_excludes'} == 1 ) {
            push @extra_tar_args, '--anchored';
        }
        my $excludes = ref $OPTS{'exclude'} eq 'ARRAY' ? $OPTS{'exclude'} : [ $OPTS{'exclude'} ];
        foreach my $exclude (@$excludes) {
            push @extra_tar_args, "--exclude=$exclude";
        }
    }

    my $source = $OPTS{'source'};
    return undef if !-e $source;

    my $target = $OPTS{'target'};
    if ( !-d $target ) {
        warn("sync_to_userdir: target: $target must be a directory");
        return undef;
    }

    # Ensure we never overwrite /XXXX or /usr/local/cpanel
    # These are various safety checks to avoid blowing away
    # any directories that should never be synced to.
    my $target_with_trailing_slash = $target;
    $target_with_trailing_slash =~ s{/+$}{};
    $target_with_trailing_slash =~ s{/+}{/}g;    # collapse /// into /
    if ( ( $target_with_trailing_slash =~ tr{/}{} ) <= 1 ) {
        die "sync_to_userdir: Cannot sync to a top level directory: “$target”.";
    }
    elsif ( $target_with_trailing_slash eq $Cpanel::ConfigFiles::CPANEL_ROOT ) {
        die "sync_to_userdir: Cannot sync to “$Cpanel::ConfigFiles::CPANEL_ROOT”.";
    }

    #return undef;
    my $target_perms = sprintf( '%04o', ( stat(_) )[2] & 07777 );

    # Case 131613, the fix (--recursive-unlink required the explicitly listing
    # the files to transfer on the tar reader command line.   This caused
    # problems when there were no files in the source directory.

    my $source_is_file = 0;
    if ( -f $source ) {
        $source_is_file = 1;
    }
    elsif ( !-d $source ) {
        die "The source “$source” must be a regular file or a directory.";
    }

    if ( !-d $target ) {
        warn("Target is not a directory: $target");
        return undef;
    }
    elsif ( !-x _ ) {
        warn("Could not access target directory: $target");
        return undef;
    }

    # A sanity check:
    if ( $OPTS{'include'} && !@{ $OPTS{'include'} } ) {
        die 'empty “include” is invalid';
    }

    my @tar_reader_child_args = (
        '--create',
        '--file' => '-',
        @extra_tar_args,

        # Since we are not writing to a .tar file only a pipe that will untar
        # we can use --sparse
        # and  case 19266 (work around for win32 bug) is not relevant
        Cpanel::Tar::OPTIMIZATION_OPTIONS(),

        # For added safety we pass the --directory flag to tar as
        # we want to ensure that no DESTROY or other handler
        # can switch the directory out from under us as this seems
        # to be possible when run though cplint
        '--directory' => $source,

        '--',
        ( $OPTS{'include'} ? @{ $OPTS{'include'} } : '.' ),
    );

    # Do not ever remove this
    die "--directory is required for safety" if !grep( m/^--directory$/, @tar_reader_child_args );

    my @tar_writer_child_args = (
        '--extract',
        $tarcfg->{'no_same_owner'},
        '--preserve-permissions',
        '--file' => '-',
        @extra_tar_args,

        #
        # As was discovered in the midst of diagnosing case 49702, it is a good
        # idea to ensure that buffer sizes on both the tarball creating and
        # tarball extracting ends match.  Since GNU tar does not complain if the
        # data written to it is smaller than its read buffer, it is safe to make
        # it attempt to read block/buffer padding beyond the file size indicated
        # in the last header read.
        #
        # In other words, passing these options to the extracting tar process is
        # fine when /bin/cat is used to "produce" the tarball stream, but is
        # definitely mandatory when greater block sizes are written by the
        # archiving tar process; if the buffer sizes don't match, then the
        # archiving tar process will complain that not all of the data it wrote
        # was written, even if this data is nul padding.
        #
        Cpanel::Tar::OPTIMIZATION_OPTIONS(),

        # For added safety we pass the --directory flag to tar as
        # we want to ensure that no DESTROY or other handler
        # can switch the directory out from under us as this seems
        # to be possible when run though cplint
        '--directory' => $target,
    );

    # Do not ever remove this
    die "--directory is required for safety" if !grep( m/^--directory$/, @tar_writer_child_args );

    my $out_pipe;
    my $in_pipe;
    pipe( $out_pipe, $in_pipe ) or die "Failed to create pipe: $!";
    Cpanel::FHUtils::Autoflush::enable($out_pipe);
    Cpanel::FHUtils::Autoflush::enable($in_pipe);

    my $tar_reader_child_pid = _spawn_reader_child(
        'in_pipe' => $in_pipe,
        ( $source_is_file ? ( 'tar_ball_path' => $source ) : ( 'base_dir' => $source ) ),
        'target_perms'             => $target_perms,
        'source_setuid'            => ( $OPTS{'source_setuid'} || 0 ),
        'tarcfg'                   => $tarcfg,
        'tar_reader_child_args_ar' => \@tar_reader_child_args,
    );

    my $tar_writer_child_pid = Cpanel::ForkAsync::do_in_child(
        sub {
            if ( $OPTS{'setuid'} ) {
                Cpanel::AccessIds::SetUids::setuids( $OPTS{'setuid'}->[0], $OPTS{'setuid'}->[1] );
            }

            chdir($target) or die "chdir($target): $!";

            # case 160525, 151613, 110645, remove public_html if it exists to allow for a
            # symlinked public_html.

            if ( $OPTS{'overwrite_public_html'} ) {
                unlink 'public_html' if ( -l 'public_html' or -f _ );
                if ( -e 'public_html' ) {
                    require File::Path;
                    File::Path::remove_tree('public_html');
                }
            }

            open( STDIN, "<&=", $out_pipe ) or die "Failed to connect STDIN to the pipe: $!";

            exec( $tarcfg->{'bin'}, @tar_writer_child_args ) or die "exec($tarcfg->{'bin'} @tar_writer_child_args): $!";
        }
    );

    close($out_pipe);

    waitpid( $tar_writer_child_pid, 0 );
    if ( $? != 0 ) {
        my $signal = $? & 0xff;
        my $status = $? >> 8;
        warn("tar_writer_child_pid exited prematurely (signal: $signal; status: $status) while working with source: $source, with arguments (@tar_writer_child_args).  The reader was called with arguments (@tar_reader_child_args)");
        kill 'KILL', $tar_reader_child_pid;
        waitpid( $tar_reader_child_pid, 0 );
        return undef;
    }

    if ( waitpid( $tar_reader_child_pid, 1 ) ) {
        if ( $? != 0 ) {
            my $signal = $? & 0x7f;
            my $status = $? >> 8;
            warn("tar_reader_child_pid exited prematurely (signal: $signal; status: $status) while working with target: $target, with arguments (@tar_reader_child_args)");
            return undef;
        }
    }

    if ( $tar_reader_child_pid && kill( 0, $tar_reader_child_pid ) > 0 ) {
        Cpanel::TimeHiRes::sleep(0.25);
        waitpid( $tar_reader_child_pid, 1 );
        if ( $tar_reader_child_pid && kill( 0, $tar_reader_child_pid ) > 0 ) {
            my $uid = $<;
            if ( $OPTS{'setuid'} ) {
                $uid = $OPTS{'setuid'}->[0];
            }
            my $user = ( getpwuid($uid) )[0];
            print STDERR "Unexpected termination.  The tar child process running as user ($user) was prematurely terminated.  The process may have been terminated by a process killer, or other event.\n";
            kill 'KILL', $tar_reader_child_pid;
            waitpid( $tar_reader_child_pid, 0 );
            if ( $? != 0 ) {
                warn("tar_reader_child_pid exited with unexpected signal while working with target: $target");
                return undef;
            }

        }
    }

    return 1;
}

sub get_strip_length {
    my ($base_dir) = @_;
    my $len = ( $base_dir =~ tr/\/// );
    return $len;
}

sub _fastspawn_reader_child {
    my (%OPTS) = @_;

    my ( $in_pipe, $tar_ball_path, $source_setuid, $base_dir, $tarcfg, $tar_reader_child_args_ar, $target_perms ) = @{OPTS}{qw(in_pipe tar_ball_path source_setuid base_dir tarcfg tar_reader_child_args_ar target_perms)};
    my $tar_reader_child_pid;

    if ($tar_ball_path) {    # cat a tar file to stdout which is connected to untar
        $tar_reader_child_pid = Proc::FastSpawn::spawn_open3(
            -1,                                     # stdin,
            fileno($in_pipe),                       # stdout
            -1,                                     # stderr
            '/bin/cat',                             # prog
            [ '/bin/cat', '--', $tar_ball_path ]    # args
        );
    }
    else {
        local $@;
        my $chdir = eval { Cpanel::Chdir->new($base_dir) };
        if ( !$chdir ) {
            warn "Failed to chdir to $base_dir: $@";
            return;
        }

        if ( defined $target_perms ) {

            # Set the source directory permissions so they are
            # the same as the target, otherwise tar while change the
            # target directory's permissions
            chmod( oct($target_perms), $base_dir ) or do {
                warn "Could not chmod $base_dir: $!";
                return;
            };
        }

        $tar_reader_child_pid = Proc::FastSpawn::spawn_open3(
            -1,                                                 # stdin,
            fileno($in_pipe),                                   # stdout
            -1,                                                 # stderr
            $tarcfg->{'bin'},                                   # prog
            [ $tarcfg->{'bin'}, @$tar_reader_child_args_ar ]    #args
        );
    }

    close($in_pipe);
    return $tar_reader_child_pid;

}

sub _spawn_reader_child {
    my (%OPTS) = @_;

    if ( $ALLOW_FASTSPAWN && !$OPTS{'source_setuid'} ) {
        goto \&_fastspawn_reader_child;
    }

    my ( $in_pipe, $tar_ball_path, $source_setuid, $base_dir, $tarcfg, $tar_reader_child_args_ar, $target_perms ) = @{OPTS}{qw(in_pipe tar_ball_path source_setuid base_dir tarcfg tar_reader_child_args_ar target_perms)};

    my $tar_reader_child_pid = Cpanel::ForkAsync::do_in_child(
        sub {
            if ($source_setuid) {
                Cpanel::AccessIds::SetUids::setuids( $source_setuid->[0], $source_setuid->[1] );
            }

            open( STDOUT, '>&=', fileno($in_pipe) ) or die "Failed to connect STDOUT to the pipe: $!";

            if ($tar_ball_path) {    # cat a tar file to stdout which is connected to untar
                exec( '/bin/cat', '--', $tar_ball_path ) or do {
                    die "Failed /bin/cat $tar_ball_path: $!";
                };
            }

            chdir($base_dir) or die "chdir($base_dir): $!";

            if ( defined $target_perms ) {

                # Set the source directory permissions so they are
                # the same as the target, otherwise tar while change the
                # target directory's permissions
                chmod( oct($target_perms), $base_dir ) or do {
                    die "Failed to chmod($base_dir): $!";
                };
            }

            exec( $tarcfg->{'bin'}, @{$tar_reader_child_args_ar} ) or do {
                die "exec($tarcfg->{'bin'} @{$tar_reader_child_args_ar}): $!";
            };
        }
    );

    close($in_pipe);
    return $tar_reader_child_pid;
}

1;
