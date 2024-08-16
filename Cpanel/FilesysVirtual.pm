package Cpanel::FilesysVirtual;

###########################################################################
### Cpanel::FilesysVirtual
### L.M.Orchard (deus_x@pobox_com)
### David Davis (xantus@cpan.org)
###
###
### Copyright (c) 1999 Leslie Michael Orchard.  All rights reserved.
### This module is free software; you can redistribute it and/or
### modify it under the same terms as Perl itself.
###
### Changes Copyright (c) 2003-2004 David Davis and Teknikill Software
###########################################################################

use strict;
use Carp                     ();
use Cpanel::IO::Mmap::Read   ();
use File::Copy               ();
use Cpanel::Fcntl::Constants ();
use IO::File                 ();

use constant SEEK_END => $Cpanel::Fcntl::Constants::SEEK_END;

our $MIN_SIZE_THAT_MMAP_IO_IS_FASTER = 16384;
our $VERSION                         = '1.0';

our %_fields = (
    'cwd'       => 1,
    'root_path' => 1,
    'home_path' => 1,
);
our $AUTOLOAD;

sub AUTOLOAD {
    my $self = shift;

    my $field = $AUTOLOAD;
    $field =~ s/.*:://;

    return if $field eq 'DESTROY';

    croak("No such property or method '$AUTOLOAD'") if ( !$self->_field_exists($field) );

    {
        no strict "refs";
        *{$AUTOLOAD} = sub {
            my $self = shift;
            return (@_) ? ( $self->{$field} = shift ) : $self->{$field};
        };
    }

    return (@_) ? ( $self->{$field} = shift ) : $self->{$field};

}

=encoding utf-8

=head1 NAME

Cpanel::FilesysVirtual - A Plain virtual filesystem

=head1 SYNOPSIS

    use Cpanel::FilesysVirtual;

    my $fs = Cpanel::FilesysVirtual->new();

    $fs->login('xantus', 'supersekret');

    print foreach ($fs->list('/'));

=head1 DESCRIPTION

This module is used by other modules to provide a pluggable filesystem.

=head1 CONSTRUCTOR

=head2 new()

You can pass the initial cwd, root_path, and home_path as a hash.

=head1 METHODS

=cut

sub new {
    my $class = shift;
    my $self  = {};
    bless( $self, $class );
    $self->_init(@_);
    return $self;
}

sub _init {
    my ( $self, $params ) = @_;

    foreach my $field ( keys %_fields ) {
        next if ( !$self->_field_exists($field) );
        $self->$field( $params->{$field} );
    }
}

sub _field_exists {
    return ( defined $_fields{ $_[1] } );
}

=pod

=head2 login($username, $password, $become)

Logs in a user.  Returns 0 on failure.  If $username is 'anonymous' then it
will try to login as 'ftp' with no password.  If $become is defined then it
will try to change ownership of the process to the uid/gid of the logged in
user.  BEWARE of the consequences of using $become.  login() also sets the
uid, gid, home, gids, home_path, and chdir to the users'.

=cut

sub login {
    my ($self) = @_;

    Carp::carp( __PACKAGE__ . "::login() Unimplemented" );

    return 0;
}

=pod

=head2 cwd

Gets or sets the current directory, assumes / if blank.
This is used in conjunction with the root_path for file operations.
No actual change directory takes place.

=cut

sub cwd {
    my $self = shift;

    if (@_) {
        $_[0] =~ s/\0.*//;    #trim after the null byte
        $self->{cwd} = shift;
    }
    else {
        $self->{cwd} ||= '/';
    }

    return $self->{cwd};
}

=pod

=head2 root_path($path)

Get or set the root path.  All file paths are  off this and cwd
For example:

    $self->root_path('/home/ftp');
    $self->cwd('/test');
    $self->size('testfile.txt');

The size command would get the size for file /home/ftp/test/testfile.txt
not /test/testfile.txt

=cut

sub root_path {
    my ($self) = shift;

    if (@_) {
        $_[0] =~ s/\0.*//;    #trim after the null byte
        my $root_path = shift;

        ### Does the root path end with a '/'?  If so, remove it.
        $root_path = ( substr( $root_path, length($root_path) - 1, 1 ) eq '/' ) ? substr( $root_path, 0, length($root_path) - 1 ) : $root_path;
        $self->{root_path} = $root_path;
    }

    return $self->{root_path};
}

=pod

=head2 chmod($mode,$file)

chmod's a file.

=cut

sub chmod {
    my ( $self, $mode, $fn ) = @_;
    $fn = $self->_path_from_root($fn);

    return ( chmod( $mode, $fn ) ) ? 1 : 0;
}

=pod

=head2 locking

This sets the file as locked or unlocked conceptually in the object so other clients can respect the locks.

A server would need to actually do whatever a[n un]lock means for it [before]after [un]locking it in the object with this.

Try five times to get a lock (tip: use a fibonacci spiral instead of full seconds):

    my $lock;

    TRY:
    for my $try(1..5) {
        $lock = $fs->lock($file);
        last TRY if $lock || $try == 5;
        sleep 1;
    }

    if($lock) {
        # open ...
        # do whatever and save
        $fs->unlock($file) or warn "lock for $file went away hope all is well...";
    }
    else {
        die "Could not lock $file!";
    }


Try it once only:

    if($fs->lock($file)) {
        # open ...
        # do whatever and save
        $fs->unlock($file) or warn "lock for $file went away hope all is well...";
    }
    else {

    }

or more linearly

    $fs->lock($file) or die "Could not lock $file!";
    # open ...
    # do whatever and save
    $fs->unlock($file) or warn "lock for $file went away hope all is well...";

An optional second argument can be passed, that if true is assigned as the value of the lock for use as a unique identifier for example.

That true value or 1 (if not given or not true) is returned on successful locking of the given file

=head3 lock($file)

get a lock on a file.

=cut

sub lock {
    my ( $self, $fn, $myvalue ) = @_;

    $fn = $self->_path_from_root($fn);
    return if exists $self->{'_locks'}{$fn};

    return $self->{'_locks'}{$fn} = $myvalue || 1;

    # or shorten race even more ??
    # return $self->{'_locks'}{ $fn } = 1 if !exists $self->{'_locks'}{ $fn };
    # return;
}

=pod

=head3 unlock($file)

unlock a locked file, returns current true value of lock if it was locked and successfully unlocked

=cut

sub unlock {
    my ( $self, $fn ) = @_;

    $fn = $self->_path_from_root($fn);
    return if !exists $self->{'_locks'}{$fn};

    return delete $self->{'_locks'}{$fn};

    # or shorten race even more ??
    # return delete $self->{'_locks'}{ $fn } if exists $self->{'_locks'}{ $fn };
    # return;
}

=pod

=head3 is_locked($file)

returns  current true value of lock or 1 if a file is locked, returns 0 if it is not

=cut

sub is_locked {
    my ( $self, $fn ) = @_;

    $fn = $self->_path_from_root($fn);
    return exists $self->{'_locks'}{$fn} ? $self->{'_locks'}{$fn} || 1 : 0;
}

=pod

=head2 modtime($file)

Gets the modification time of a file in YYYYMMDDHHMMSS format.

=cut

sub modtime {
    my ( $self, $fn ) = @_;
    $fn = $self->_path_from_root($fn);

    my (
        $dev,   $ino,   $mode,  $nlink,   $uid, $gid, $rdev, $size,
        $atime, $mtime, $ctime, $blksize, $blocks
    ) = CORE::stat($fn);

    my ( $sec, $min, $hr, $dd, $mm, $yy, $wd, $yd, $isdst ) = localtime($mtime);
    $yy += 1900;
    $mm++;

    return "$yy$mm$dd$hr$min$sec";
}

=pod

=head2 size($file)

Gets the size of a file in bytes.

=cut

sub size {
    my ( $self, $fn ) = @_;
    $fn = $self->_path_from_root($fn);

    return ( CORE::stat($fn) )[7];
}

=pod

=head2 delete($file)

Deletes a file, returns 1 or 0 on success or failure.

=cut

sub delete {
    my ( $self, $fn ) = @_;
    $fn = $self->_path_from_root($fn);

    return ( ( -e $fn ) && ( !-d $fn ) && ( unlink($fn) ) ) ? 1 : 0;
}

=pod

=head2 chdir($dir)

Changes the cwd to a new path from root_path.
Returns undef on failure or the new path on success.

=cut

sub chdir {
    my ( $self, $dir ) = @_;

    my $new_cwd   = $self->_resolve_path($dir);
    my $full_path = $self->root_path() . $new_cwd;

    return ( ( -e $full_path ) && ( -d $full_path ) ) ? $self->cwd($new_cwd) : undef;
}

=pod

=head2 mkdir($dir, $mode)

Creats a directory with $mode (defaults to 0755) and chown()'s the directory
with the uid and gid.  The return value is from mkdir().

=cut

sub mkdir {
    my ( $self, $dir, $mode ) = @_;
    $dir = $self->_path_from_root($dir);

    return 2 if ( -d $dir );

    $mode ||= 0755;

    my $ret = ( mkdir( $dir, $mode ) ) ? 1 : 0;

    if ($ret) {
        chown( $self->{uid}, $self->{gid}, $dir );
    }
    return $ret;
}

=pod

=head2 rmdir($dir)

Deletes a directory or file if -d test fails.  Returns 1 on success or 0 on
failure.

=cut

sub rmdir {
    my ( $self, $dir ) = @_;
    $dir = $self->_path_from_root($dir);

    if ( -e $dir ) {
        if ( -d $dir ) {
            return 1 if ( rmdir($dir) );
        }
        else {
            return 1 if ( unlink($dir) );
        }
    }

    return 0;
}

=pod

=head2 list($dir)

Returns an array of the files in a directory.

=cut

sub list {
    my ( $self, $dirfile ) = @_;
    $dirfile = $self->_path_from_root($dirfile);

    my @ls;

    if ( opendir( my $dir_fh, $dirfile ) ) {
        @ls = sort readdir($dir_fh);
        close($dir_fh);
    }
    elsif ( !-d $dirfile ) {
        ### This isn't a directory, so derive its short name, and push it.
        my @parts = split( /\//, $dirfile );
        push( @ls, pop @parts );
    }

    return wantarray ? @ls : \@ls;
}

=pod

=head2 list_details($dir)

Returns an array of the files in ls format.

=cut

sub list_details {
    my ($self) = @_;

    Carp::carp( __PACKAGE__ . "::list_details() Unimplemented" );

    return undef;
}

=pod

=head2 stat($file)

Does a normal stat() on a file or directory

=cut

sub stat {
    my ( $self, $fn ) = @_;

    $fn = $self->_path_from_root($fn);

    return CORE::stat($fn);
}

=pod

=head2 test($test,$file)

Perform a perl type test on a file and returns the results.

For example to perform a -d on a directory.

    $self->test('d','/testdir');

See filetests in perlfunc (commandline: perldoc perlfunc)

=cut

#    -r  File is readable by effective uid/gid.
#    -w  File is writable by effective uid/gid.
#    -x  File is executable by effective uid/gid.
#    -o  File is owned by effective uid.

#    -R  File is readable by real uid/gid.
#    -W  File is writable by real uid/gid.
#    -X  File is executable by real uid/gid.
#    -O  File is owned by real uid.

#    -e  File exists.
#    -z  File has zero size.
#    -s  File has nonzero size (returns size).

#    -f  File is a plain file.
#    -d  File is a directory.
#    -l  File is a symbolic link.
#    -p  File is a named pipe (FIFO), or Filehandle is a pipe.
#    -S  File is a socket.
#    -b  File is a block special file.
#    -c  File is a character special file.
#    -t  Filehandle is opened to a tty.

#    -u  File has setuid bit set.
#    -g  File has setgid bit set.
#    -k  File has sticky bit set.

#    -T  File is a text file.
#    -B  File is a binary file (opposite of -T).

#    -M  Age of file in days when script started.
#    -A  Same for access time.
#    -C  Same for inode change time.

sub test {
    my ( $self, $test, $fn ) = @_;

    $fn = $self->_path_from_root($fn);

    # NO FUNNY BUSINESS
    $test =~ s/^(.)/$1/;

    if ( $test eq 'r' ) {
        return -r $fn;
    }
    elsif ( $test eq 'w' ) {
        return -w $fn;
    }
    elsif ( $test eq 'x' ) {
        return -x $fn;
    }
    elsif ( $test eq 'o' ) {
        return -o $fn;
    }
    elsif ( $test eq 'R' ) {
        return -R $fn;
    }
    elsif ( $test eq 'W' ) {
        return -W $fn;
    }
    elsif ( $test eq 'X' ) {
        return -X $fn;
    }
    elsif ( $test eq 'O' ) {
        return -O $fn;
    }
    elsif ( $test eq 'e' ) {
        return -e $fn;
    }
    elsif ( $test eq 'z' ) {
        return -z $fn;
    }
    elsif ( $test eq 's' ) {
        return -s $fn;
    }
    elsif ( $test eq 'f' ) {
        return -f $fn;
    }
    elsif ( $test eq 'd' ) {
        return -d $fn;
    }
    elsif ( $test eq 'l' ) {
        return -l $fn;
    }
    elsif ( $test eq 'p' ) {
        return -p $fn;
    }
    elsif ( $test eq 'S' ) {
        return -S $fn;
    }
    elsif ( $test eq 'b' ) {
        return -b $fn;
    }
    elsif ( $test eq 'c' ) {
        return -c $fn;
    }
    elsif ( $test eq 't' ) {
        return -t $fn;
    }
    elsif ( $test eq 'u' ) {
        return -u $fn;
    }
    elsif ( $test eq 'g' ) {
        return -g $fn;
    }
    elsif ( $test eq 'k' ) {
        return -k $fn;
    }
    elsif ( $test eq 'T' ) {
        return -T $fn;
    }
    elsif ( $test eq 'B' ) {
        return -B $fn;
    }
    elsif ( $test eq 'M' ) {
        return -M $fn;
    }
    elsif ( $test eq 'A' ) {
        return -A $fn;
    }
    elsif ( $test eq 'C' ) {
        return -C $fn;
    }

    return undef;
}

=pod

=head2 open_read($file,[params])

Opens a file with L<IO::File>. Params are passed to open() of IO::File.
It returns the file handle on success or undef on failure.  This could
be technically be used for any sort of open operation.  See L<IO::File>'s
open method.

If the file is larger than 16KiB, this returns a Cpanel::IO::Mmap::Read
instance; otherwise, this returns an IO::File. Mmap is much more CPU
efficient for all but the smallest files.

#Cpanel::IO::Mmap::Read does not provide all the functionality of
#that’s compatible with IO::File.
#
#sysseek(), binmode(), chmod(), etc. are not provided, however
#we currently do not need them.  If that changes they will be implemented
#later

=cut

sub open_read {
    my ( $self, $fin ) = @_;
    $self->{file_path} = $fin = $self->_path_from_root($fin);

    my $obj = IO::File->new( $fin, '<' );
    if ( ( $obj->stat )[7] > $MIN_SIZE_THAT_MMAP_IO_IS_FASTER ) {
        return Cpanel::IO::Mmap::Read->new($obj);
    }

    return $obj;

}

=pod

=head2 close_read($fh)

Performs a $fh->close()

=cut

sub close_read {
    my ( $self, $fh ) = @_;

    return $fh->close();
}

=pod

=head2 open_write($fh, $append)

Performs an $fh->open(">$file") or $fh->open(">>$file") if $append is defined.
Returns the filehandle on success or undef on failure.

=cut

sub open_write {
    my ( $self, $fin, $append ) = @_;
    $self->{file_path} = $fin = $self->_path_from_root($fin);
    return IO::File->new( $fin, ( $append ? '>>' : '>' ) );
}

=pod

=head2 close_write($fh)

Performs a $fh->close()

=cut

sub close_write {
    my ( $self, $fh ) = @_;

    $fh->close();

    return 1;
}

=pod

=head2 seek($fh, $pos, $wence)

Performs a $fh->seek($pos, $wence). See L<IO::Seekable>.

=cut

sub seek {
    my ( $self, $fh, $first, $second ) = @_;

    return $fh->seek( $first, $second );
}

=pod

=head2 utime($atime, $mtime, @files)

Performs a utime() on the file(s).  It changes the access time and mod time of
those files.

=cut

sub utime {
    my ( $self, $atime, $mtime, @fn ) = @_;

    foreach my $i ( 0 .. $#fn ) {
        $fn[$i] = $self->_path_from_root( $fn[$i] );
    }

    return CORE::utime( $atime, $mtime, @fn );
}

### Internal methods

# Restrict the path to beneath root path

sub _path_from_root {
    my ( $self, $path ) = @_;

    $path =~ s/\0.*//;    #trim after the null byte

    return $self->root_path() . $self->_resolve_path($path);
}

# Resolve a path from the current path

sub _resolve_path {
    my $self = shift;
    my $path = shift;
    $path = '' unless defined $path;

    my $cwd      = $self->cwd();
    my $path_out = '';

    if ( $path eq '' ) {
        $path_out = $cwd;
    }
    elsif ( $path eq '/' ) {
        $path_out = '/';
    }
    else {
        my @real_ele = split( /\//, $cwd );
        if ( $path =~ m/^\// ) {
            undef @real_ele;
        }
        foreach ( split( /\//, $path ) ) {
            if ( $_ eq '..' ) {
                pop(@real_ele) if ($#real_ele);
            }
            elsif ( $_ eq '.' ) {
                next;
            }
            elsif ( $_ eq '~' ) {
                @real_ele = split( /\//, $self->home_path() );
            }
            else {
                push( @real_ele, $_ );
            }
        }
        $path_out = join( '/', @real_ele );
    }

    $path_out = ( substr( $path_out, 0, 1 ) eq '/' ) ? $path_out : '/' . $path_out;

    $path_out =~ /(.*)/;
    $path_out = $1;

    return $path_out;
}

sub copy {
    my $self = shift;
    $self->_fileop( 'copy', @_ );
}

sub move {
    my $self = shift;
    $self->_fileop( 'move', @_ );
}

sub _fileop {
    my ( $self, $op, $fin, $fout ) = @_;
    $fin  = $self->_path_from_root($fin);
    $fout = $self->_path_from_root($fout);

    return ( $op eq 'copy' ? File::Copy::copy( $fin, $fout ) : File::Copy::move( $fin, $fout ) );

}

1;

__END__

=head1 AUTHOR

David Davis, E<lt>xantus@cpan.orgE<gt>, http://teknikill.net/

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

perl(1), L<Filesys::Virtual>, L<Filesys::Virtual::SSH>,
L<Filesys::Virtual::DAAP>, L<POE::Component::Server::FTP>,
L<Net::DAV::Server>, L<HTTP::Daemon>,
http://perladvent.org/2004/20th/

=cut
