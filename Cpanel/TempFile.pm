package Cpanel::TempFile;

# cpanel - Cpanel/TempFile.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::TempFile - easy generation and cleanup of temp files and dirs

=head1 SYNOPSIS

    my $tf = Cpanel::TempFile->new();
    my ($path, $wfh) = $tf->file();

    my $dpath = $tf->dir();

    my $tf2 = Cpanel::TempFile->new( { path => '/base/path' } );

    #^^ By no means is the above complete! Feel free to expand on it.

=cut

use strict;
use warnings;

use Cpanel::Rand        ();
use Cpanel::Debug       ();
use Cpanel::SafeDir::MK ();
use Cpanel::SafeDir::RM ();
use Cpanel::Fcntl       ();
use Cpanel::Debug       ();
use Cpanel::Destruct    ();
use Cwd                 ();

my $DO_OPEN   = $Cpanel::Rand::DO_OPEN;
my $SKIP_OPEN = $Cpanel::Rand::SKIP_OPEN;
my $TYPE_DIR  = $Cpanel::Rand::TYPE_DIR;
my $TYPE_FILE = $Cpanel::Rand::TYPE_FILE;

our $DEFAULT_PATH = '/var/tmp';
my $DEFAULT_SUFFIX = 'tmp';

# The following three initial subroutines remain from the old, non-OO interface.
sub get_safe_tmpfile {
    return get_safe_tmp_file_or_dir( $Cpanel::Rand::TYPE_FILE, @_ );
}

sub get_safe_tmpdir {
    return get_safe_tmp_file_or_dir( $Cpanel::Rand::TYPE_DIR, @_ );
}

sub get_safe_tmp_file_or_dir {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $file_or_dir = shift;
    my $homedir     = $Cpanel::homedir;
    if ( !$homedir ) {
        require Cpanel::PwCache;
        $homedir = Cpanel::PwCache::gethomedir();
    }
    if ( !-d $homedir . '/tmp' ) {
        if ( !mkdir( $homedir . '/tmp', 0755 ) ) {
            Cpanel::Debug::log_warn("Failed to create $homedir/tmp");
            return;
        }
    }
    return Cpanel::Rand::get_tmp_file_by_name( $homedir . '/tmp/Cpanel::TempFile', '.tmp', $file_or_dir, @_ );    # audit case 46806 ok
}

sub new {
    my ( $what, $opts ) = @_;
    my $class = ref $what || $what;
    my $self  = {};
    bless $self, $class;

    $self->set_opts($opts);
    $self->{"needunlink_$$"} = [];

    return $self;
}

sub dir {
    my ( $self, @other_args ) = @_;
    return $self->_dir_or_file( $TYPE_DIR, @other_args );
}

sub file {
    my ( $self, @other_args ) = @_;
    return $self->_dir_or_file( $TYPE_FILE, @other_args );
}

# Like file, but create the file in its own temporary directory.  This is useful
# for the case where cache files or other files we might want to discard can be
# created.
sub file_in_dir {
    my ( $self, @other_args ) = @_;
    my $dir  = $self->dir(@other_args);
    my $opts = pop @other_args || {};
    return $self->_dir_or_file( $TYPE_FILE, @other_args, { %$opts, 'path' => $dir } );
}

sub file_readwrite {

    # Unlike std Perl module File::Temp, and for solely historical reasons, perhaps,
    # Cpanel::Rand::get_tmp_file_by_name() returns a write-only filehandle. And thus so does
    # file() of this module, which really just wraps said Rand subroutine. So here we
    # provide a facility for obtaining a R/W filehandle, which is what some of our tests
    # expect. This may not be the best solution, but at least it is localized for future
    # modification, if necessary. (Thanks to Dan M. for recommending this approach.)

    my ( $self, @other_args ) = @_;

    if ( !wantarray ) {
        $self->_warn("Calling file_readwrite() in scalar context makes no sense, since you will only get back a filename but no filehandle");
        return;
    }

    my ( $fname, $fh ) = $self->file(@other_args);

    close $fh;
    undef $fh;

    my $mode = Cpanel::Fcntl::or_flags(qw( O_RDWR O_EXCL ));

    sysopen( $fh, $fname, $mode, 0600 )
      or $self->_die("Could not sysopen $fname: $!\n");

    return ( $fname, $fh );
}

sub filename_only {
    my $self = shift;

    my $die_msg = "You must not call filename_only() to get a unique temp file name not backed by an actual";
    $die_msg .= " file on disk. The subroutine is not implemented and with good reason; see case 48668";
    $self->_die($die_msg);

    # Likewise, this module always calls Cpanel::Rand::get_tmp_file_by_name() with $DO_OPEN;
    # the file or dir is ALWAYS created. Calling file() or dir() of this module in list vs.
    # scalar context only controls whether or not an open file (dir) handle is returned
    # alongside the file (dir) name, but not whether or not the temp file (dir) itself is
    # actually created; it ALWAYS is. (I.e. in this module, but not so in Cpanel::Rand, where
    # that is the default behavior, but it can be overridden with $SKIP_OPEN). }
}

sub set_opts {
    my ( $self, $opts ) = @_;

    my @valid_keys = qw( suffix prefix path debug mkdirs );
    my $err;
    foreach my $key ( sort keys %{$opts} ) {
        next if grep { $key eq $_ } @valid_keys;
        $self->_warn("Disallowing invalid opt '$key' passed in opts hash");
        $err = 1;
    }

    return if $err;

    $opts //= {};
    $self->{'opts'} //= {};

    my @debug;
    foreach my $k ( sort keys %{$opts} ) {
        my $v = $opts->{$k} // '';
        $self->{'opts'}->{$k} = $v;
        push @debug, "Set opt $k = $v";
    }

    $Cpanel::Debug::level = $self->{'opts'}->{'debug'} ? 1 : 0;
    $self->_debug($_) for (@debug);
    return 1;
}

sub _get_opt {
    my ( $self, $name, $opts ) = @_;

    return $opts->{$name} || $self->{'opts'}->{$name};
}

#Last argument can be a hashref:
#   prefix (default q{})
#   path (default /var/tmp)
#   suffix (tmp)
#   mkdirs (make "path" if it's not there already)
sub _dir_or_file {    # Main workhorse of this module
    my ( $self, $dir_or_file, @other_args ) = @_;

    my $opts     = {};
    my $last_arg = $other_args[$#other_args];
    if ( ref $last_arg eq "HASH" ) {
        pop @other_args;
        $opts = $last_arg;
    }

    # The subroutine in Rand.pm that we will be calling allows $SKIP_OPEN, but we do not, which is why
    # filename_only() in this module is left to die() unimplemented. See case 48668.
    my $open = $DO_OPEN;

    my $prefix = $self->_get_opt( 'prefix', $opts ) || "";
    if ( length $prefix ) {

        # We treat slash as a special case of \W , because user likely is
        # misktakenly using prefix instead of path.

        if ( $prefix =~ m{/} ) {
            $self->_warn("You must not specify a prefix containing '/' ; instead, use the 'path' option for that purpose");
            return;
        }

        if ( $prefix =~ m{[^-.\w]} ) {
            $self->_warn("Bad prefix '$prefix', prefix must contain only '.', '-', and \\w characters");
            return;
        }
    }

    my $caller = _callername();
    substr $prefix, 0, 0, substr( $caller, length $caller > 40 ? -40 : 0 ) . '__' if $caller;
    substr $prefix, 0, 0, "$$" . '.';

    my $path   = $self->_get_opt( 'path',   $opts ) || $DEFAULT_PATH;
    my $suffix = $self->_get_opt( 'suffix', $opts ) || $DEFAULT_SUFFIX;

    substr $prefix, 0, 0, "$path/";

    if ( !-e $path ) {
        if ( $self->_get_opt( 'mkdirs', $opts ) ) {
            my @created;
            if ( Cpanel::SafeDir::MK::safemkdir( $path, undef, undef, \@created ) && -e $path ) {
                $self->_info("Have created path '$path'");
                push @{ $self->{"needunlink_$$"} }, @created;
            }
            else {
                $self->_warn("Non-existent path '$path', could not create");
            }
        }
        else {
            $self->_warn("Non-existent path '$path', will not create, because mkdirs option is not set");
        }
    }

    my ( $fname, $fh ) = Cpanel::Rand::get_tmp_file_by_name( $prefix, $suffix, $dir_or_file, $open );
    undef $fname if defined $fname && $fname eq "/dev/null";

    $fname = $self->_make_suffix_rightmost( $fname, $suffix );

    push @{ $self->{"needunlink_$$"} }, $fname if defined $fname;
    return ( $fname, $fh ) if wantarray;
    return $fname;
}

sub _make_suffix_rightmost {

    # This fix should be made directly to Cpanel::Rand::get_tmp_file_by_name(), but we dare
    # not break any code that might --God only knows-- rely on the status-quo behavior.

    my ( $self, $fname, $suffix ) = @_;
    if ( defined $fname ) {
        my $orig = $fname;
        if ( $fname =~ s{ ^ (.*) [.] ($suffix) [.] (.*) }{ "$1.$3.$2" }ex ) {
            if ( -e $orig ) {
                if ( !rename $orig, $fname ) {
                    $self->_warn("Could not rename '$orig' to '$fname' to shift suffix ('$suffix') to rightmost position, leaving as is");
                    $fname = $orig;
                }
            }
        }
        else {
            print STDERR "Regular expression substitution failed to adjust '$orig' to shift suffix ('$suffix') to rightmost position\n";
        }
    }
    return $fname;
}

sub _info {
    my ( $self, $msg ) = @_;
    return Cpanel::Debug::log_info($msg);
}

sub _warn {
    my ( $self, $msg ) = @_;
    return Cpanel::Debug::log_warn($msg);
}

sub _debug {
    my ( $self, $msg ) = @_;
    return unless $Cpanel::Debug::level;
    return Cpanel::Debug::log_debug($msg);
}

sub _die {
    my ( $self, $msg ) = @_;
    return Cpanel::Debug::log_die($msg);
}

{
    # _callername cache
    my $caller;

    sub _callername {
        return $caller if defined $caller;
        ( $caller = $0 ) =~ s{\W}{_}g;
        $caller = uc $caller;
        return $caller;
    }

    # freeze callername at compilation time
    BEGIN { _callername() }
}

sub cleanup {
    my $self = shift;

    return unless defined $self->{"needunlink_$$"} && ref $self->{"needunlink_$$"};

    # Sort puts long names first, maximizes 'Removed' and minimizes 'Not removed' debug/ log messages.
    # Note: we now always cleanup on DESTROY since we track by pid.
    my @needunlink = reverse @{ $self->{"needunlink_$$"} };

    for my $file (@needunlink) {
        if ( ( $file =~ tr/\/// ) < 1 ) {
            $self->_warn("Not removed: $file, as a temp file cannot be at top level");    # ok to not remove because invalid
        }
        elsif ( $file eq '/dev/null' ) {                                                  # at this writing we need this, unfortunately
            $self->_warn("Not removed: /dev/null, I flatly refuse to remove it");
        }
        else {
            my $file_or_dir = -d $file ? "directory" : "file";
            my $existed     = -e _;
            if ( !$existed ) {
                $self->_debug("Not removing $file_or_dir $file, does not exist; perhaps already removed in a recursive dir cleanup, or by some other removal agent");
            }
            else {
                if ( $file_or_dir eq 'directory' ) {

                    #We’re likely in a DESTROY handler at this point.
                    #If we’re also in a propagating exception that
                    #doesn’t get caught, then as of January 2016 every
                    #known Perl version will exit 0 (!) in response to
                    #$? being set to 0 by safermdir().
                    #cf. https://rt.perl.org/Ticket/Display.html?id=127386
                    local $?;
                    my $old_dir  = Cwd::abs_path( Cwd::getcwd($file) );
                    my $abs_path = Cwd::abs_path($file);
                    if ( $old_dir eq $abs_path ) {
                        $self->_warn("The cwd is temporary directory “$file”. The cwd was changed to “$file/..” in order to remove the temporary directory.");
                        chdir("$file/..") or die "Failed to chdir('$file/..'): $!";
                    }
                    Cpanel::SafeDir::RM::safermdir($file);
                }
                else {
                    unlink($file);
                }

                my $intro = $existed && !-e $file ? "R" : "Not r";
                $self->_debug("${intro}emoved: $file_or_dir $file");
            }
        }
    }

    @{ $self->{"needunlink_$$"} } = ();
    return;
}

sub needunlink {
    my ( $self, $item ) = @_;
    push @{ $self->{"needunlink_$$"} }, $item;
    return;
}

sub DESTROY {
    my $self = shift;

    return if Cpanel::Destruct::in_dangerous_global_destruction();

    #NOTE: Do this regardless of PID because we now track by PID and
    # only remove temp files that this process created.
    #
    # If we only did this for the parent process, then any temp files/dirs
    # that a child process created would be left behind because it would
    # have a different pid from the original object even though it
    # created the temp file.
    #
    $self->cleanup();

    return;
}

1;
