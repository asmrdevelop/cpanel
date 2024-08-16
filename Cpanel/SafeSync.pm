package Cpanel::SafeSync;

# cpanel - Cpanel/SafeSync.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use Cwd                                  ();
use Cpanel::PwCache                      ();
use Fcntl                                ();
use Cpanel::Debug                        ();
use Cpanel::Tar                          ();
use Cpanel::SafeSync::UserDir            ();
use Cpanel::Rand                         ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::SafeFind                     ();
use File::Find                           ();    #required for binaries
use Cpanel::LoadFile                     ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::SafeRun::Simple              ();
use Cpanel::FastSpawn::InOut             ();
use Cpanel::SafeRun::Simple              ();
use Cpanel::TempFile                     ();
use Umask::Local                         ();
use Cpanel::SV                           ();

my $default_exclude = '/usr/local/cpanel/etc/cpbackup-exclude.conf';
our $global_exclude  = '/etc/cpbackup-exclude.conf';
our $MAX_CACHE_DEPTH = 10;

our $INCLUDE_CPANEL_CONTROLLED_DIRS = 0;
our $SKIP_CPANEL_CONTROLLED_DIRS    = 1;

*sync_to_userdir             = *Cpanel::SafeSync::UserDir::sync_to_userdir;
*find_gid_files_from_tarball = *find_uid_files_from_tarball;
*find_gid_files              = *find_uid_files;

# find_uid_files_from_tarball
#
# This is much faster then find_uid_files because it does not have to stat thousands of files
#
#   Parameter List:
#           tarfile : tar file to look though
#           uidlist  : List of group names.
#   Returns: Hash, keys are full pathnames of destination
#           files.  Value is a user name of the group if one of the
#           groups from uidlist was able to read the file.
sub find_uid_files_from_tarball {
    my ( $tarfile, $uidlist ) = @_;

    my %FILES_OWNED_BY_OTHER_UIDS;
    my $tarcfg = Cpanel::Tar::load_tarcfg();

    my %USERLIST;
    foreach my $group ( @{$uidlist} ) {
        my $user = ( Cpanel::PwCache::getpwnam_noshadow($group) )[0];
        $USERLIST{$user} = $group;
    }

    my $parser_ok = 0;
    my @tarargs   = ( '-t', '-v', '-f', $tarfile );
    if ( $tarcfg->{'dashdash_utc'} ) { push @tarargs, '--utc'; }

    my $tarpid = Cpanel::FastSpawn::InOut::inout( my $wtrtar, my $rdrtar, $tarcfg->{'bin'}, @tarargs );
    close($wtrtar);

    #
    # Parse TAR
    #
    my $user;
    my $argsize;
    while ( readline($rdrtar) ) {

        #-rw-r--r-- root/wheel    31651 Mar 25 01:25 2008 Class-Std-0.0.9.tar.gz            [gnu tar <1.14]
        #-rw-r--r-- root/root      6171 2006-09-25 14:37 asterisk-addons-1.4.1/Makefile     [gnu tar 1.14+]
        #-rw-r--r--  0 root   wheel   31651 Mar 25  2008 Class-Std-0.0.9.tar.gz             [bsdtar       ]
        if (m/^\S+\s+([^\/]+)\/\S+\s+\d+\s+\d+/) {    # [gnu tar 1.14+]
            $user    = $1;
            $argsize = 5;
        }
        elsif (m/^\S+\s+([^\/]+)\/\S+\s+\d+/) {       #[gnu tar <1.14]
            $user    = $1;
            $argsize = 7;
        }
        elsif (m/^\S+\s+\d+\s+(\S+)\s+\S+/) {         # BSD Tar
            $user    = $1;
            $argsize = 8;
        }
        else {
            next;
        }

        $parser_ok = 1;

        if ( exists $USERLIST{$user} ) {
            my $relfile;
            my @TAROUT = split( /\s+/, $_ );
            splice( @TAROUT, 0, $argsize );    #splice off everything but the file
            if ( $#TAROUT > 0 ) {              #there are more spaces to deal with
                for ( 0 .. $#TAROUT ) {        #now check for a symlink and discard anything after the ->
                    if ( $TAROUT[$_] eq '->' ) {
                        splice( @TAROUT, $_ );
                        last;
                    }
                }

                #reassemble with just the file;
                $relfile = join( ' ', @TAROUT );
            }
            else {
                $relfile = $TAROUT[0];
            }
            $relfile =~ s/^\.\///g;    #strip leading ./

            $FILES_OWNED_BY_OTHER_UIDS{$relfile} = $user;
        }
    }

    waitpid( $tarpid, 0 );
    return ( $parser_ok, \%FILES_OWNED_BY_OTHER_UIDS );
}

sub build_global_cpbackup_exclude_conf {
    my %global_excludes;

    # Fetch default cPanel excludes
    if ( open my $global_exclude_fh, '<', $default_exclude ) {
        while ( my $line = readline $global_exclude_fh ) {
            chomp $line;
            next if $line =~ m/\A\s*\z/s;
            next if $line =~ m/\A\s*#/s;
            $global_excludes{$line} = 1;
        }
        close $global_exclude_fh;
    }
    else {
        Cpanel::Debug::log_warn("Failed to read $default_exclude: $!");
        return;
    }

    # Fetch any locally created system excludes
    my $system_exclude_fh;
    if ( -e $global_exclude ) {
        if ( open $system_exclude_fh, '+<', $global_exclude ) {
            while ( my $line = readline $system_exclude_fh ) {
                chomp $line;
                next if $line =~ m/\A\s*\z/s;
                next if $line =~ m/\A\s*#/s;
                next if $line eq 'core.*';    # Remove bad exclude from previous versions
                $global_excludes{$line} = 1;
            }
            seek( $system_exclude_fh, 0, 0 );
            truncate( $system_exclude_fh, tell($system_exclude_fh) );
        }
        else {
            Cpanel::Debug::log_warn("Failed to read $global_exclude: $!");
            return;
        }
    }

    # Create a new system exclude configuration
    else {
        open $system_exclude_fh, '>', $global_exclude or do {
            Cpanel::Debug::log_warn("Failed to write new $global_exclude: $!");
            return;
        }
    }

    # Write updated values
    foreach my $exclude ( sort keys %global_excludes ) {
        print {$system_exclude_fh} $exclude . "\n";
    }
    close $system_exclude_fh;

    return;
}

# build_cpbackup_exclude_conf
#   Parameter List:
#           dir : Dir to look for files
sub build_cpbackup_exclude_conf {
    my ($src) = @_;

    if ( !-d $src ) {
        print "Source must be a directory.\n";
        return;
    }

    if ( !-e $global_exclude || -z _ || ( stat(_) )[9] < ( stat($default_exclude) )[9] ) {
        print "rebuilding system exclude file\n";
        build_global_cpbackup_exclude_conf();
    }

    return ( -e $src . '/cpbackup-exclude.conf' ) ? 1 : 0;

    # We used to search the home directory for the old
    # .cpbackup-skip files to convert them to the cpbackup-exclude.conf
    # however this has been going on since 2009 and everyone
    # should definately be converted by now so it has been removed.
    #

}

# find_uid_files
#   Parameter List:
#           dir : Dir to look for files
#           uidlist  : List of group names.
#           user: user to run File::Find as. Will default to current running user (usually root) if not specified.
#   Returns: Hash, keys are full pathnames of destination
#           files.  Value is a user name of the group if one of the
#           groups from uidlist was able to read the file.
sub find_uid_files {
    my ( $src, $uidlist, $user, $skip_cpanel_controlled_dirs ) = @_;

    my %FILES_OWNED_BY_OTHER_UIDS;
    if ( !-d $src ) {
        print "Source must be a directory.\n";
        return;
    }
    $src = Cwd::abs_path($src) // $src;

    my %UIDLIST;
    foreach my $group ( @{$uidlist} ) {
        my $t_uid = ( Cpanel::PwCache::getpwnam_noshadow($group) )[2];
        $UIDLIST{$t_uid} = $group;
    }

    my $filefind_coderef = sub {
        Cpanel::SafeFind::find(
            {
                'no_chdir' => 1,
                'wanted'   => sub {
                    if (
                        $skip_cpanel_controlled_dirs
                        && (   index( $File::Find::name, "$src/mail/" ) == 0
                            || index( $File::Find::name, "$src/etc/" ) == 0
                            || index( $File::Find::name, "$src/tmp/" ) == 0
                            || index( $File::Find::name, "$src/ssl/" ) == 0
                            || index( $File::Find::name, "$src/.cpanel/" ) == 0 )
                    ) {
                        $File::Find::prune = 1;
                        return;
                    }
                    elsif ( defined $UIDLIST{ ( lstat($File::Find::name) )[4] } ) {    # [4] is uid
                        next if ( $File::Find::name eq $src );
                        $FILES_OWNED_BY_OTHER_UIDS{$File::Find::name} = $UIDLIST{ ( lstat(_) )[4] };
                    }
                }
            },
            $src
        );
    };

    $user && !$> ? Cpanel::AccessIds::ReducedPrivileges::call_as_user( $filefind_coderef, $user ) : $filefind_coderef->();

    return \%FILES_OWNED_BY_OTHER_UIDS;
}

# safesync -
#   Parameter Hash:
#           user      : Username of owner.
#           gidlist   : List of group names.
#           source    : Path to source directory.
#           dest      : Path to destination directory.
#           callback  : Optional callback reference to be used
#                       instead of copy.
#           exclude   : OPTIONAL, A regex to compare filenames against,
#                       if file matches, the file will be excluded
#                       from the copy process.
#           delete    : Boolean, if true safesync will delete all
#                       files in dest that are not in source.
#           verbose   : Boolean, if true safesync will print
#                       detailed information on its actions.
#           link_dest : if using rsync an optional parameter is
#                       link_dest that uses hard links to minimize
#                       disk size.
#
#   Returns: Hash, keys are full pathnames of destination
#           files.  Value is a group name if one of the
#           groups from gidlist was able to read the file.
sub safesync {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my %OPTS = @_;

    my %FILES_OWNED_BY_OTHER_UIDS;
    my @xferlist;
    my ( $user_uid, $user_gid ) = ( Cpanel::PwCache::getpwnam_noshadow( $OPTS{'user'} ) )[ 2, 3 ];

    my $setup_dest = _setup_dest( $OPTS{'dest'}, $OPTS{'source'} );
    if ( !$setup_dest ) {
        print "Failed to setup destination for copy ($OPTS{'dest'}).\n";
        return;
    }
    if ( !-d $OPTS{'source'} ) {
        print "Source $OPTS{'source'} must be a directory.\n";
        return;
    }
    $OPTS{'source'} = Cwd::abs_path( $OPTS{'source'} ) // $OPTS{'source'};

    $OPTS{'dest'} = Cwd::abs_path( $OPTS{'dest'} ) // $OPTS{'dest'};

    my %UIDLIST;
    foreach my $group ( @{ $OPTS{'gidlist'} } ) {
        my $t_uid = $group =~ tr{0-9}{}c ? ( Cpanel::PwCache::getpwnam_noshadow($group) )[2] : $group;
        $UIDLIST{$t_uid} = $group;
    }

    my $arg_size = 0;

    my $basedir = $> == 0 ? '/var/cpanel/safesync' : Cpanel::PwCache::gethomedir( Cpanel::PwCache::getusername() ) . '/safesync';

    {
        my $umask = Umask::Local->new(022);
        Cpanel::SafeDir::MK::safemkdir( $basedir, '0711' ) if !-e $basedir;
    }

    my @EXCLUDE_LIST;
    if ( $OPTS{'isbackup'} ) {
        if ( -r $OPTS{'source'} . '/cpbackup-exclude.conf' ) {
            if ( $user_uid && ( stat( $OPTS{'source'} . '/cpbackup-exclude.conf' ) )[7] < 512000 ) {
                my $privs = Cpanel::AccessIds::ReducedPrivileges->new( $OPTS{'user'} );
                @EXCLUDE_LIST = split( /\n/, Cpanel::LoadFile::loadfile( $OPTS{'source'} . '/cpbackup-exclude.conf' ) );
            }
            else {
                if ( open( my $cp_fh, '<', $OPTS{'source'} . '/cpbackup-exclude.conf' ) ) {
                    while ( my $line = readline $cp_fh ) {
                        chomp $line;
                        next if $line =~ m/\A\s*\z/s;
                        next if $line =~ m/\A\s*#/s;
                        push @EXCLUDE_LIST, $line;
                    }
                    close($cp_fh);
                }
            }
        }

        if ( open my $sys_excludes_fh, '<', $global_exclude ) {
            while ( my $line = readline $sys_excludes_fh ) {
                chomp $line;
                next if $line =~ m/\A\s*\z/s;
                next if $line =~ m/\A\s*#/s;
                push @EXCLUDE_LIST, $line;
            }
            close $sys_excludes_fh;
        }
    }

    my %SLICED_EXCLUDE_LIST;
    if (@EXCLUDE_LIST) {
        foreach my $exclude (@EXCLUDE_LIST) {
            next unless length $exclude;
            if ( $exclude =~ m/\*/ ) {    # Coming from:  info '(tar.info)exclude'
                my @BUILD_EXCLUDES;

                # Convert shell wild card characters to their Perl cousins
                if ( $exclude =~ s/^\*\/// ) {
                    push @BUILD_EXCLUDES, '^' . $exclude;
                    push @BUILD_EXCLUDES, '/' . $exclude;
                }
                else {
                    push @BUILD_EXCLUDES, $exclude;
                }
                foreach my $regex_exclude_part (@BUILD_EXCLUDES) {
                    $regex_exclude_part =~ s/\//\\\//g;
                    $regex_exclude_part =~ s/\./\\./g;
                    $regex_exclude_part =~ s/\*/.*/g;
                    $regex_exclude_part =~ s/\?/./g;
                    $regex_exclude_part =~ s/\[\!/[^/g;             # This one is not precise, but it shouldn't be a problem
                    $regex_exclude_part =~ s/\.\*$/\[\^\\\/\]\*/;
                    $SLICED_EXCLUDE_LIST{ $regex_exclude_part . '$' }  = undef;
                    $SLICED_EXCLUDE_LIST{ $regex_exclude_part . '\/' } = undef;
                }
            }
            else {
                $exclude =~ s/\/+$//;

                #print STDERR "[cpbackup] Adding perl exclude - \"$exclude\"\n";
                $SLICED_EXCLUDE_LIST{ '^' . quotemeta($exclude) . '$' }  = undef;
                $SLICED_EXCLUDE_LIST{ '^' . quotemeta($exclude) . '\/' } = undef;
            }
        }
    }
    @EXCLUDE_LIST = ();
    $SLICED_EXCLUDE_LIST{ '^' . quotemeta('public_ftp/.ftpquota') . '$' } = undef if $OPTS{'pkgacct'};

    my @OK_REGEXS;    #hash to slice;

    for my $exclude ( keys %SLICED_EXCLUDE_LIST ) {
        {
            no warnings 'uninitialized';    ## no critic qw(TestingAndDebugging::ProhibitNoWarnings)
            eval { m/(?:$exclude)/ };
        }
        if ($@) {
            print STDERR "[cpbackup] Rejecting regex '$exclude' because it failed to compile: $@\n";
        }
        else {
            push @OK_REGEXS, $exclude;
        }
    }

    my $exclude_code_ref;

    if (@OK_REGEXS) {
        my $exclude_re = join '|', map { "(?:$_)" } @OK_REGEXS;
        $exclude_code_ref = sub {
            return ( $_[0] =~ /$exclude_re/ );
        };
    }

    my $use_exclude_regex = ( ref $exclude_code_ref ? 1 : 0 );
    my $source            = $OPTS{'source'};
    $source =~ s/\/+/\//;
    $source =~ s/\/$//;
    my $dest = $OPTS{'dest'};
    $dest =~ s/\/+/\//;
    $dest =~ s/\/$//;

    my $verbose           = $OPTS{'verbose'};
    my $use_exclude_opt   = exists $OPTS{'exclude'} ? 1                    : 0;
    my $opt_exclude_regex = $OPTS{'exclude'}        ? qr/$OPTS{'exclude'}/ : undef;    #cannot use /o here

    #
    #   These variables MUST be reset each loop.
    #   They are scoped outside the block to save the allocation work that my() has to do
    #
    my ( $relfile, $absfile, $s_isregfile, $s_mode, $s_uid, $s_islnk, $s_isdir );

    my ( $excludelistname, $excludelistfh ) = _setup_syncfile( $basedir, "excludelist", $user_uid, $user_gid );

    my $safefindcr = sub {
        Cpanel::SafeFind::find(
            {
                'no_chdir' => 1,
                'wanted'   => sub {
                    $relfile = _get_relative_filename( $File::Find::name, $source );
                    if ( $use_exclude_regex && $exclude_code_ref->($relfile) ) {
                        print "Skipping $relfile\n";
                        print {$excludelistfh} $relfile . "\0";
                        $File::Find::prune = 1;
                        return;
                    }
                    if ($use_exclude_opt) {
                        $absfile = $File::Find::name;
                        $absfile =~ tr{/}{}s;
                        $absfile =~ s{/$}{};
                        if ( $opt_exclude_regex && $absfile =~ $opt_exclude_regex ) {
                            print "Excluding File: $absfile\n" if $verbose;
                            print {$excludelistfh} $relfile . "\0";
                            $File::Find::prune = 1;
                            return;
                        }
                    }

                    ( $s_mode, $s_uid ) = ( lstat($File::Find::name) )[ 2, 4 ];
                    ( $s_isregfile, $s_islnk, $s_isdir ) = ( ( ( $s_mode & 0170000 ) == 0100000 ? 1 : 0 ), ( ( $s_mode & 0170000 ) == 0120000 ? 1 : 0 ), ( ( $s_mode & 0170000 ) == 0040000 ? 1 : 0 ) );
                    if ( !$s_isdir && !$s_islnk && !$s_isregfile ) {
                        print {$excludelistfh} $relfile . "\0";
                        return;
                    }

                    if ( exists $UIDLIST{$s_uid} ) {
                        $FILES_OWNED_BY_OTHER_UIDS{$absfile} = $UIDLIST{$s_uid};
                    }
                },
            },
            $OPTS{'source'}
        );
    };

    $user_uid ? Cpanel::AccessIds::ReducedPrivileges::call_as_user( $user_uid, $safefindcr ) : $safefindcr->();

    close($excludelistfh);

    _synclist( $excludelistname, $OPTS{'source'}, $OPTS{'dest'}, $user_uid, $user_gid, %OPTS );

    unlink($excludelistname);

    return \%FILES_OWNED_BY_OTHER_UIDS;
}

sub _synclist {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::ProhibitManyArgs)
    my ( $xferref, $source, $dest, $read_uid, $read_gid, %OPTS ) = @_;

    my $filelist;

    # determine if xferref is an array of files, convert to file list for
    # rsync
    if ( ref($xferref) eq "ARRAY" ) {
        my $temp_obj = Cpanel::TempFile->new();
        my ( $temp_file, $temp_fh ) = $temp_obj->file();
        foreach my $file ( @{$xferref} ) {
            print $temp_fh "$file\0";
        }
    }
    else {
        $filelist = $xferref;
    }

    # Call rsync with all flags we need

    my $link_dest = $OPTS{'link_dest'};    # full path

    my $username = Cpanel::PwCache::getusername($read_uid);
    if ( !$username ) {
        Cpanel::Debug::log_die("Could not get username from the UID “$read_uid”, backup can not proceed.");
    }
    my @rsync_cmd;

    push( @rsync_cmd, 'rsync' );
    push( @rsync_cmd, '--archive', '--human-readable' );
    push( @rsync_cmd, '--from0' );
    push( @rsync_cmd, '--no-owner', '--no-group' );
    push( @rsync_cmd, '--delete-excluded' ) if $OPTS{'delete'};
    push( @rsync_cmd, "--exclude-from=$filelist" );
    push( @rsync_cmd, "--link-dest=$link_dest" ) if exists $OPTS{'link_dest'} && -d $OPTS{'link_dest'};
    push( @rsync_cmd, '--rsh' => '/usr/local/cpanel/bin/run_as_user' );
    push( @rsync_cmd, $username . ':' . $source . '/' );                                                  # user:/path/to/source/
    push( @rsync_cmd, $dest );

    my $results = Cpanel::SafeRun::Simple::saferun(@rsync_cmd);
    print $results . "\n";
    return;
}

sub _setup_dest {
    my ( $dest, $src ) = @_;
    if ( !-e $dest ) {
        print "Destination does not exist ($dest), creating.\n";
        my ( $mode, $uid, $gid, $s_mod ) = ( stat($src) )[ 2, 4, 5, 9 ];
        if ( !mkdir($dest) ) {
            die "Unable to create destination directory ($dest). Failing.\n";
        }
        chmod( $mode & 00777, $dest );
        utime( time, $s_mod, $dest );
        return 1;
    }
    elsif ( !-d $dest ) {
        return 0;
    }
    else {
        return 1;
    }
}

sub _setup_syncfile {
    my ( $path, $name, $uid, $gid ) = @_;
    my ( $tmpfile, $fh ) = Cpanel::Rand::get_tmp_file_by_name("$path/$name.$uid");    # audit case 46806 ok
    Cpanel::SV::untaint($tmpfile);
    if ($tmpfile) {
        chmod 0640, $tmpfile;                                                         # get_tmp_file_by_name makes this 0600 by default
        chown 0, $gid, $tmpfile;
    }
    return ( $tmpfile, $fh );
}

sub _get_relative_filename {
    return $_[0] eq $_[1] ? '/' : substr( $_[0], length( $_[1] ) + 1 );
}

1;
